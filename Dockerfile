FROM debian:buster-slim

# -------------------------------------------------------------------
# Toolchain Version Config
# -------------------------------------------------------------------

# Espressif toolchain
ARG ESP_VERSION="1.22.0-80-g6c4433a-5.2.0"

# esp-idf framework
ARG IDF_VERSION="master"

# llvm-xtensa
ARG LLVM_VERSION="654ba115e55638acc60a8dacf8b1b8d8468cc4f4"

# rust-xtensa
ARG RUSTC_VERSION="cf75e7f9a189657830a5619ce51a2891a618232c"

# -------------------------------------------------------------------
# Toolchain Path Config
# -------------------------------------------------------------------

ARG TOOLCHAIN="/home/esp32-toolchain"

ARG ESP_BASE="${TOOLCHAIN}/esp"
ENV ESP_PATH "${ESP_BASE}/esp-toolchain"
ENV IDF_PATH "${ESP_BASE}/esp-idf"

ARG LLVM_BASE="${TOOLCHAIN}/llvm"
ARG LLVM_BUILD_PATH="${LLVM_BASE}/llvm_build"
ARG LLVM_INSTALL_PATH="${LLVM_BASE}/llvm_install"

ARG RUSTC_BASE="${TOOLCHAIN}/rustc"
ARG RUSTC_PATH="${RUSTC_BASE}/rust_xtensa"
ARG RUSTC_BUILD_PATH="${RUSTC_BASE}/rust_build"

ENV PATH "/root/.cargo/bin:${ESP_PATH}/bin:${PATH}"

# -------------------------------------------------------------------
# Install expected depdendencies
# -------------------------------------------------------------------

RUN apt-get update \
 && apt-get install -y \
       bison \
       cmake \
       curl \
       flex \
       g++ \
       gcc \
       git \
       gperf \
       libncurses-dev \
       make \
       ninja-build \
       python \
       python-pip \
       wget \
       pkg-config \
       libssl-dev \
 && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# Setup esp32 toolchain
# -------------------------------------------------------------------

WORKDIR "${ESP_BASE}"
RUN curl \
       --proto '=https' \
       --tlsv1.2 \
       -sSf \
       -o "${ESP_PATH}.tar.gz" \
       "https://dl.espressif.com/dl/xtensa-lx106-elf-linux64-1.22.0-100-ge567ec7-5.2.0.tar.gz" \
 && mkdir "${ESP_PATH}" \
 && tar -xzf "${ESP_PATH}.tar.gz" -C "${ESP_PATH}" --strip-components 1 \
 && rm -rf "${ESP_PATH}.tar.gz"

# -------------------------------------------------------------------
# Setup esp-idf
# -------------------------------------------------------------------

WORKDIR "${ESP_BASE}"
RUN  git clone \
       --recursive --single-branch -b "${IDF_VERSION}" \
       https://github.com/espressif/ESP8266_RTOS_SDK.git \
 && mv ESP8266_RTOS_SDK ${IDF_PATH} \
 && pip install --user -r "${IDF_PATH}/requirements.txt"

# -------------------------------------------------------------------
# Build llvm-xtensa
# -------------------------------------------------------------------

WORKDIR "${LLVM_BASE}"
RUN git clone https://github.com/espressif/llvm-project.git \
  && cd llvm-project/ \
  && git checkout ${LLVM_VERSION}
RUN mkdir ${LLVM_BUILD_PATH} && cd ${LLVM_BUILD_PATH} \
  && cmake ${LLVM_BASE}/llvm-project/llvm/ \
       -DLLVM_TARGETS_TO_BUILD="X86" \
       -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="Xtensa" \
       -DLLVM_INSTALL_UTILS=ON \
       -DLLVM_BUILD_TESTS=0 \
       -DLLVM_INCLUDE_TESTS=0 \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX="${LLVM_INSTALL_PATH}" \
       -DCMAKE_CXX_FLAGS="-w" \
       -DLLVM_ENABLE_PROJECTS="clang" \
       -G "Ninja" \
  && cmake --build . \
  && cmake --build . --target install \
  && rm -r ${LLVM_BASE}/llvm-project

# -------------------------------------------------------------------
# Build rust-xtensa
# -------------------------------------------------------------------

WORKDIR "${RUSTC_BASE}"
RUN git clone \
        --recursive --single-branch \
        https://github.com/MabezDev/rust-xtensa.git \
        "${RUSTC_PATH}"

RUN mkdir -p "${RUSTC_BUILD_PATH}" \
 && cd "${RUSTC_PATH}" \
 && git checkout ${RUSTC_VERSION} \
 && ./configure \
        --llvm-root "${LLVM_INSTALL_PATH}" \
        --prefix "${RUSTC_BUILD_PATH}" \
 && python ./x.py build \
 && python ./x.py install

# -------------------------------------------------------------------
# Setup rustup toolchain
# -------------------------------------------------------------------

RUN curl \
        --proto '=https' \
        --tlsv1.2 \
        -sSf \
        https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable \
 && rustup component add rustfmt \
 && rustup toolchain link xtensa "${RUSTC_BUILD_PATH}" \
 && cargo install cargo-xbuild bindgen

# IDF project

WORKDIR /home
RUN mkdir idf-project/ && mkdir idf-project/main/

WORKDIR /home/idf-project
COPY templates/Makefile .
COPY templates/component.mk main/
COPY templates/main.c main/

# Freertos shim

WORKDIR /home
COPY freertos-shim.diff /
RUN git clone https://github.com/hashmismatch/freertos.rs.git \
  && cd freertos.rs \
  && git checkout d52f8b8695ee3c8d399d5e9e73e97908acf4dbf0 \
  && git apply --ignore-space-change --ignore-whitespace /freertos-shim.diff \
  && cp shim/freertos_rs.c /home/idf-project/main/

# esp8266-sys crate

COPY esp8266-sys/ /home/esp8266-sys/

# -------------------------------------------------------------------
# Our Project
# -------------------------------------------------------------------

ENV PROJECT="/home/project/"

ENV XARGO_RUST_SRC="${RUSTC_PATH}/src"
ENV TEMPLATES="${TOOLCHAIN}/templates"
ENV LIBCLANG_PATH="${LLVM_INSTALL_PATH}/lib"
ENV CARGO_HOME="${PROJECT}target/cargo"

VOLUME "${PROJECT}"
WORKDIR "${PROJECT}"

COPY menuconfig bindgen-project build-project create-project image-project xbuild-project flash-project /usr/local/bin/
COPY templates/ "${TEMPLATES}"

CMD ["/bin/bash"]
