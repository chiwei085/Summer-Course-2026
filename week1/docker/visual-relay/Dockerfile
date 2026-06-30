# syntax=docker/dockerfile:1.7

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS base-build
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        ccache \
        cmake \
        g++ \
        git \
        ninja-build \
        pkg-config \
        python3 \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libwayland-dev \
        libx11-dev \
        libxext-dev \
        libxrandr-dev \
        libxcursor-dev \
        libxi-dev \
        libxkbcommon-dev \
    && rm -rf /var/lib/apt/lists/*
ENV CCACHE_DIR=/ccache \
    CMAKE_CXX_COMPILER_LAUNCHER=ccache

FROM base-build AS dependencies
ARG SDL3_TAG=release-3.2.0
WORKDIR /third_party
RUN --mount=type=cache,target=/ccache \
    git clone --depth 1 --branch ${SDL3_TAG} https://github.com/libsdl-org/SDL.git SDL3 && \
    cmake -S SDL3 -B /build/sdl3 -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/deps \
        -DSDL_TEST_LIBRARY=OFF && \
    cmake --build /build/sdl3 --target install

FROM base-build AS source-base
WORKDIR /src
COPY CMakeLists.txt ./
COPY include ./include
COPY src/protocol ./src/protocol
COPY src/common ./src/common
COPY assets ./assets

FROM dependencies AS gui-source-base
WORKDIR /src
COPY CMakeLists.txt ./
COPY include ./include
COPY src/protocol ./src/protocol
COPY src/common ./src/common
COPY assets ./assets

FROM source-base AS simulator-build
COPY src/relay_simulator ./src/relay_simulator
RUN --mount=type=cache,target=/ccache \
    --mount=type=cache,target=/build/visual-relay-simulator \
    cmake -S /src -B /build/visual-relay-simulator -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/visual-relay \
        -DVISUAL_RELAY_BUILD_TESTS=OFF \
        -DVISUAL_RELAY_BUILD_SCOUT=OFF \
        -DVISUAL_RELAY_BUILD_CATCHER=OFF && \
    cmake --build /build/visual-relay-simulator --target relay_simulator && \
    DESTDIR=/install cmake --install /build/visual-relay-simulator --component Unspecified

FROM gui-source-base AS scout-build
COPY src/scout_station ./src/scout_station
RUN --mount=type=cache,target=/ccache \
    --mount=type=cache,target=/build/visual-relay-scout \
    cmake -S /src -B /build/visual-relay-scout -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/deps \
        -DCMAKE_INSTALL_PREFIX=/opt/visual-relay \
        -DVISUAL_RELAY_BUILD_TESTS=OFF \
        -DVISUAL_RELAY_BUILD_SIMULATOR=OFF \
        -DVISUAL_RELAY_BUILD_CATCHER=OFF && \
    cmake --build /build/visual-relay-scout --target scout_station && \
    DESTDIR=/install cmake --install /build/visual-relay-scout --component Unspecified

FROM gui-source-base AS catcher-build
COPY src/catcher_station ./src/catcher_station
RUN --mount=type=cache,target=/ccache \
    --mount=type=cache,target=/build/visual-relay-catcher \
    cmake -S /src -B /build/visual-relay-catcher -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/opt/deps \
        -DCMAKE_INSTALL_PREFIX=/opt/visual-relay \
        -DVISUAL_RELAY_BUILD_TESTS=OFF \
        -DVISUAL_RELAY_BUILD_SIMULATOR=OFF \
        -DVISUAL_RELAY_BUILD_SCOUT=OFF && \
    cmake --build /build/visual-relay-catcher --target catcher_station && \
    DESTDIR=/install cmake --install /build/visual-relay-catcher --component Unspecified

FROM base-build AS test
WORKDIR /src
COPY CMakeLists.txt ./
COPY include ./include
COPY src/protocol ./src/protocol
COPY src/common ./src/common
COPY assets ./assets
COPY tests ./tests
COPY grader ./grader
RUN --mount=type=cache,target=/ccache \
    cmake -S /src -B /build/visual-relay-test -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DVISUAL_RELAY_BUILD_APPS=OFF \
        -DVISUAL_RELAY_BUILD_TESTS=ON && \
    cmake --build /build/visual-relay-test && \
    ctest --test-dir /build/visual-relay-test --output-on-failure

FROM ubuntu:${UBUNTU_VERSION} AS runtime-base
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 \
        libgcc-s1 \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 visualrelay \
    && useradd --system --uid 10001 --gid visualrelay --home-dir /nonexistent --shell /usr/sbin/nologin visualrelay \
    && mkdir -p /opt/visual-relay/bin
COPY scripts/healthcheck-service.sh /opt/visual-relay/bin/healthcheck-service.sh
USER visualrelay:visualrelay
WORKDIR /opt/visual-relay

FROM runtime-base AS gui-runtime-base
USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libgl1 \
        libegl1 \
        libwayland-client0 \
        libx11-6 \
        libxext6 \
        libxrandr2 \
        libxcursor1 \
        libxi6 \
        libxkbcommon0 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/deps/lib
COPY --from=dependencies /opt/deps/lib/libSDL3.so /opt/deps/lib/
COPY --from=dependencies /opt/deps/lib/libSDL3.so.0 /opt/deps/lib/
COPY --from=dependencies /opt/deps/lib/libSDL3.so.0.2.0 /opt/deps/lib/
ENV LD_LIBRARY_PATH=/opt/deps/lib \
    XDG_CACHE_HOME=/tmp/visual-relay-cache \
    MESA_SHADER_CACHE_DIR=/tmp/visual-relay-cache/mesa
USER visualrelay:visualrelay

FROM runtime-base AS simulator-runtime
COPY --from=simulator-build /install/opt/visual-relay /opt/visual-relay
ENTRYPOINT ["/opt/visual-relay/bin/relay-simulator"]

FROM gui-runtime-base AS scout-runtime
COPY --from=scout-build /install/opt/visual-relay /opt/visual-relay
ENTRYPOINT ["/opt/visual-relay/bin/scout-station"]

FROM gui-runtime-base AS catcher-runtime
COPY --from=catcher-build /install/opt/visual-relay /opt/visual-relay
ENTRYPOINT ["/opt/visual-relay/bin/catcher-station"]
