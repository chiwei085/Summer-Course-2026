# Week 3: Camera Calibration Lab

This lab is a small C++20 camera calibration project. It calibrates a pinhole
camera from real chessboard sample images and pre-extracted corner observations.
The goal is to understand the calibration math, not to spend lab time debugging
checkerboard corner detection.

The project uses no OpenCV, Eigen. The calibration math
itself only vendors `stb_image.h`, wrapped behind a C++20 RAII boundary in
`include/week3/calibration/image.hpp` and `src/image.cpp`. The optional
notebook UI (below) additionally vendors [Mongoose](https://github.com/cesanta/mongoose)
(dual-licensed GPL-2.0 / commercial &mdash; see `third_party/mongoose/mongoose.h`)
and `nlohmann/json`, the same third-party set `week3/color` uses.

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

## Interactive Notebook

The same calibration core is also exposed as a notebook-style web UI (served
over HTTP by a vendored [Mongoose](https://github.com/cesanta/mongoose)
server, same pattern as `week3/color`), so the summary above doesn't have to
be read off a terminal:

```bash
./build/calibration_notebook data
# defaults: data, http://0.0.0.0:8080
```

Then open the printed address in a browser. It has three linked cells:

1. **Calibration summary** &mdash; board spec, intrinsic matrix `K`,
   `fx/fy/cx/cy/skew`, and the overall RMS reprojection error, recomputed
   live instead of printed to stdout.
2. **Reprojection overlay** &mdash; pick a view and see its observed corners
   (green), the corners reprojected through the current intrinsics and that
   view's pose (red), and the error segment between each pair. A good fit
   makes the two nearly coincide.
3. **Per-view error & include/exclude** &mdash; every view's RMS in one
   table, with views far above the rest of the set flagged `suspicious`.
   Unchecking a view drops it from calibration and reruns everything
   (intrinsics, RMS, every view's reprojection) without it; at least 3
   included views are required. Excluded views can still be selected in the
   overlay above &mdash; their pose is a closed-form estimate against the
   current intrinsics rather than the jointly refined one, since they no
   longer take part in calibration.

## Data

Images are OpenCV sample chessboard images `left01.jpg` through `left14.jpg`.
Only the images and an offline-generated `observations.csv` are used by this
project. OpenCV is not a dependency of the C++ build.

See `data/provenance.md` for source, license, and corner extraction details.
