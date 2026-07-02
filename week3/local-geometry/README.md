# week3 / local-geometry

An interactive, notebook-style demo of classic local-feature and geometric-
primitive detectors, implemented from scratch in C++20 (no OpenCV) and
served over HTTP by a vendored [Mongoose](https://github.com/cesanta/mongoose)
server. Open the page in a browser and it behaves like a live Jupyter
notebook: every slider calls back into the C++ backend, which does the
actual pixel math and returns JSON or PNG.

## What's inside

0. **Shared foundation** &mdash; grayscale conversion (BT.601 luma) and
   Sobel image gradients (G<sub>x</sub>, G<sub>y</sub>, magnitude,
   orientation), computed once in `week3::local_geometry::sobel_gradients`
   and reused by every topic below.
1. **Edge detection** &mdash; non-max suppression along the gradient
   direction followed by double-threshold hysteresis (Canny), over
   `images/scissors.png`. Low/high thresholds are interactive.
2. **Corner detection** &mdash; the structure tensor (windowed sums of
   I<sub>x</sub>&sup2;, I<sub>y</sub>&sup2;, I<sub>x</sub>I<sub>y</sub>),
   its eigenvalues (shown worked out with LaTeX, alongside a table mapping
   eigenvalue combinations to flat/edge/corner geometry), Harris response
   `det(M) - k*trace(M)^2`, and non-max suppression to pick isolated peaks,
   over `images/building.jpg`. `k`, the response threshold, the structure
   tensor's window radius, and the non-max-suppression radius are all
   interactive.
3. **Line detection** &mdash; a standard (&rho;, &theta;) Hough transform
   over Canny edge points, greedy peak picking, and a line-segment
   extraction pass (project nearby edge points onto each detected line,
   split on gaps) over `images/solidWhiteRight.jpg`. Every Hough and
   segment-extraction parameter is interactive: the Canny thresholds that
   feed it, the vote threshold, theta/rho accumulator step sizes, max line
   count, the minimum theta/rho separation between kept peaks, and the
   segment extraction's max point distance, max gap, and min length.

Corner and line results come back as JSON point/segment lists and are drawn
on an HTML canvas layered over the source image, the same overlay pattern
`week3/calibration`'s reprojection diagnostics use. Edge and gradient
results come back as PNG bytes straight from the backend, the same pattern
`week3/color` uses for its intensity images.

## Layout

Header-heavy, Rust-flavored API: small `.hpp` files own the public surface,
most `.cpp` files are a page or two, errors are returned as `Result<T, E>`
rather than thrown, and the HTTP layer is built through a `Builder` rather
than mutable setters.

```
include/week3/local_geometry/   public headers (result.hpp, image.hpp,
                                 gradient.hpp, edges.hpp, corners.hpp,
                                 lines.hpp, server.hpp, api.hpp)
src/                             matching .cpp files + main.cpp
web/                             the notebook frontend (vanilla HTML/CSS/JS,
                                 no build step, no CDN dependencies; math is
                                 typeset with the vendored KaTeX build served
                                 from /vendor/katex)
third_party/                     vendored stb_image / stb_image_write,
                                 nlohmann/json, Mongoose (dual-licensed
                                 GPL-2.0 / commercial -- see
                                 third_party/mongoose/mongoose.h), and KaTeX
                                 (MIT, third_party/katex/LICENSE)
images/                          all sample images together: scissors.png
                                 (no separate license, same treatment as
                                 week3/color/images/mortis.png), plus the
                                 downloaded building.jpg and
                                 solidWhiteRight.jpg with provenance.md and
                                 the vendored licenses those two require
```

## Build & run

```sh
cmake -S . -B build -G Ninja
cmake --build build -j
./build/local_geometry_notebook [listen_address]
# default: http://0.0.0.0:8080
# (the three sample images are always loaded from images/scissors.png,
#  images/building.jpg, and images/solidWhiteRight.jpg)
```

Then open the printed address in a browser.

`cmake --build build --target format` / `format-check` run clang-format over
every header and source file.

## Image licensing

`images/scissors.png` needs no separate license action (see above).
`images/building.jpg` (OpenCV sample data, Apache License 2.0) and
`images/solidWhiteRight.jpg` (Udacity `CarND-LaneLines-P1` sample data,
MIT License) are documented in full, including exact source URLs, in
`images/provenance.md`, with the licenses themselves vendored as
`images/OPENCV_LICENSE.txt` and `images/CARND_LANELINES_LICENSE.txt`.
