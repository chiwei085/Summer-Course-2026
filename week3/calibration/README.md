# Week 3: Camera Calibration Lab

This lab is a small C++20 camera calibration project. It calibrates a pinhole
camera from real chessboard sample images and pre-extracted corner observations.
The goal is to understand the calibration math, not to spend lab time debugging
checkerboard corner detection.

The project uses no OpenCV, Eigen, or Conan dependency. The only vendored
third-party code is `stb_image.h`, wrapped behind a C++20 RAII boundary in
`include/week3/calibration/image.hpp` and `src/image.cpp`.

## Build and Run

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/calibrate_camera data
```

Expected result: the program prints the intrinsic matrix, per-view extrinsics,
and an overall RMS reprojection error below `3.0 px` for the pinhole-only model.
Reaching sub-pixel error on these real sample images requires lens distortion
estimation and usually nonlinear refinement, which are optional extensions.

## Data

Images are OpenCV sample chessboard images `left01.jpg` through `left14.jpg`.
Only the images and an offline-generated `observations.csv` are used by this
project. OpenCV is not a dependency of the C++ build.

See `data/provenance.md` for source, license, and corner extraction details.
