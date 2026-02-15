# Copyright 2023 by the SpinalHDL Docker contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# Author(s): Pavel Benacek <pavel.benacek@gmail.com>
#            Leuenberger Niklaus <https://github.com/NikLeberg>

ARG UBUNTU_VERSION=22.04
FROM ubuntu:$UBUNTU_VERSION AS base

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$PATH:/opt/bin"

ARG DEPS_RUNTIME="ca-certificates gnupg2 openjdk-17-jdk-headless ccache curl g++ gcc git libtcl8.6 python3 python3-pip python3-pip-whl libpython3-dev ssh locales make iverilog libboost1.74-dev fish"
RUN apt-get update && \
    apt-get install -y --no-install-recommends $DEPS_RUNTIME \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build-symbiyosys

ENV PREFIX=/opt
ARG DEPS_YOSYS="autoconf build-essential clang cmake libffi-dev libreadline-dev pkg-config tcl-dev unzip flex bison libz-dev"
RUN apt-get update \
    && apt-get install -y --no-install-recommends $DEPS_YOSYS \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG YOSYS_VERSION="yosys-0.41"
RUN git clone https://github.com/YosysHQ/yosys.git yosys && \
    cd yosys && \
    git checkout $YOSYS_VERSION && \
    make PREFIX=$PREFIX -j4 && \
    make PREFIX=$PREFIX install && \
    cd .. && \
    rm -Rf yosys

ARG TARGETARCH
RUN mkdir solver && cd solver && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        SOLVERS_ZIP="ubuntu-22.04-ARM64-bin.zip"; \
    else \
        SOLVERS_ZIP="ubuntu-22.04-X64-bin.zip"; \
    fi && \
    curl -o solvers.zip -sL "https://github.com/GaloisInc/what4-solvers/releases/download/snapshot-20260119/${SOLVERS_ZIP}" && \
    unzip solvers.zip && \
    rm solvers.zip && \
    chmod +x * && \
    cp cvc4 $PREFIX/bin/cvc4 && \
    cp cvc5 $PREFIX/bin/cvc5 && \
    cp z3 $PREFIX/bin/z3 && \
    cp yices $PREFIX/bin/yices && \
    cp yices-smt2 $PREFIX/bin/yices-smt2 && \
    cd .. && rm -rf solver

ARG BOOLECTOR_VERSION="3.2.2"
RUN curl -L "https://github.com/Boolector/boolector/archive/refs/tags/$BOOLECTOR_VERSION.tar.gz" \
      | tar -xz \
    && cd boolector-$BOOLECTOR_VERSION \
    && ./contrib/setup-lingeling.sh \
    && ./contrib/setup-btor2tools.sh \
    && ./configure.sh --prefix $PREFIX \
    && make PREFIX=$PREFIX -C build -j4 \
    && make PREFIX=$PREFIX -C build install \
    && cd .. \
    && rm -Rf boolector-$BOOLECTOR_VERSION

ARG SYMBIYOSYS_VERSION="yosys-0.41"
RUN git clone https://github.com/YosysHQ/sby.git SymbiYosys && \
    cd SymbiYosys && \
    git checkout $SYMBIYOSYS_VERSION && \
    make PREFIX=$PREFIX -j4 install && \
    cd .. && \
    rm -Rf SymbiYosys

FROM base AS build-verilator

ENV PREFIX=/opt
ARG DEPS_VERILATOR="perl make autoconf g++ flex bison ccache libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev zlib1g zlib1g-dev help2man"
RUN apt-get update \
    && apt-get install -y --no-install-recommends $DEPS_VERILATOR \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG VERILATOR_VERSION="v5.036"
RUN git clone https://github.com/verilator/verilator verilator && \
    cd verilator && \
    git checkout $VERILATOR_VERSION && \
    autoconf && \
    ./configure --prefix $PREFIX && \
    make PREFIX=$PREFIX -j4 && \
    make PREFIX=$PREFIX install && \
    cd ../.. && \
    rm -Rf verilator

FROM base AS build-spinal

ENV PREFIX=/opt
ARG MILL_VERSION="0.11.11"
ARG SBT_VERSION="1.9.9"

ENV COURSIER_CACHE=$PREFIX/cache/coursier
ENV MILL_CACHE_PATH=$PREFIX/cache/mill
ENV SBT_OPTS="-Dsbt.global.base=$PREFIX/cache/sbt/global -Dsbt.boot.directory=$PREFIX/cache/sbt/boot -Dsbt.ivy.home=$PREFIX/cache/ivy2 -Dsbt.rootdir=true"

RUN mkdir -p $PREFIX/bin $PREFIX/cache

# Install Mill
RUN curl -L -o /usr/local/bin/mill https://github.com/lihaoyi/mill/releases/download/$MILL_VERSION/$MILL_VERSION && \
    chmod +x /usr/local/bin/mill && \
    mill --version

# Install SBT
RUN curl -L -o sbt-$SBT_VERSION.tgz https://github.com/sbt/sbt/releases/download/v$SBT_VERSION/sbt-$SBT_VERSION.tgz && \
    tar -xzf sbt-$SBT_VERSION.tgz -C $PREFIX --strip-components=1 && \
    rm sbt-$SBT_VERSION.tgz && \
    $PREFIX/bin/sbt sbtVersion

FROM base AS run

ARG MILL_VERSION="0.11.11"
ENV MILL_VERSION=$MILL_VERSION
ENV PREFIX=/opt
ENV COURSIER_CACHE=$PREFIX/cache/coursier
ENV MILL_CACHE_PATH=$PREFIX/cache/mill
ENV SBT_OPTS="-Dsbt.global.base=$PREFIX/cache/sbt/global -Dsbt.boot.directory=$PREFIX/cache/sbt/boot -Dsbt.ivy.home=$PREFIX/cache/ivy2 -Dsbt.rootdir=true"
ENV PATH="$PATH:$PREFIX/bin"

RUN python3 -m pip install --no-cache-dir cocotb==2.0.1 cocotb-test click

RUN git config --system --add safe.directory '*'

COPY --from=build-symbiyosys /opt /opt
COPY --from=build-verilator /opt /opt
COPY --from=build-spinal /opt /opt
COPY --from=build-spinal /usr/local/bin/mill /usr/local/bin/mill