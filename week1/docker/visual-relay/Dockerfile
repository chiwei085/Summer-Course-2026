# One image with everything inside: toolchain, dependency sources, project
# sources, and all three services. It works, and that is the only good thing
# about it.
#
# TODO: make ./grader/grade.sh fully green. Its [FAIL] lines are the spec.
# Among other things it will demand from this file:
#
#   - a multi-stage layout, with these stage names when you are done:
#       base-build, dependencies, test,
#       simulator-runtime, scout-runtime, catcher-runtime
#     (`docker build --target test .` must run the unit tests as part of
#      the build, and the three *-runtime stages are what compose deploys)
#   - rebuilds that do not redo work whose inputs did not change
#   - pinned, reproducible versions
#   - runtime images with no toolchain, no sources, and no root
#
# The package names, cmake flags, and install prefix below are correct.
# Everything about how they are arranged is yours to fix.

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
        ca-certificates \
        cmake \
        g++ \
        git \
        pkg-config \
        python3 \
        netcat-openbsd \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libwayland-dev \
        libx11-dev \
        libxext-dev \
        libxrandr-dev \
        libxcursor-dev \
        libxi-dev \
        libxkbcommon-dev

COPY . /src

# SDL3 is not packaged on Ubuntu 24.04, so it has to be built from source.
RUN git clone --depth 1 --branch release-3.2.0 \
        https://github.com/libsdl-org/SDL.git /src/sdl3-src && \
    cmake -S /src/sdl3-src -B /src/sdl3-build \
        -DCMAKE_BUILD_TYPE=Release \
        -DSDL_TEST_LIBRARY=OFF && \
    cmake --build /src/sdl3-build -j"$(nproc)" && \
    cmake --install /src/sdl3-build && \
    ldconfig

RUN cmake -S /src -B /src/app-build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/visual-relay && \
    cmake --build /src/app-build -j"$(nproc)" && \
    cmake --install /src/app-build

WORKDIR /opt/visual-relay
