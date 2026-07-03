# week3 / homework &mdash; Snake (Active Contour)

An interactive, notebook-style implementation of the classic Snake / active
contour algorithm (Kass, Witkin &amp; Terzopoulos, 1988; basic greedy
formulation from Williams &amp; Shah, 1992), implemented from scratch in
C++20 (no OpenCV) and served over HTTP by a vendored
[Mongoose](https://github.com/cesanta/mongoose) server, following the same
framework as `week3/color` and `week3/local-geometry`.

## What's inside

0. **Shared foundation** &mdash; grayscale conversion (BT.601 luma), a
   hand-rolled separable Gaussian blur, and 3&times;3 Sobel gradients, all
   implemented from first principles in `filters.hpp`/`filters.cpp` and
   reused by everything below.
1. **A deliberately crude automatic initial contour** (`initial_contour.hpp`,
   its own header, independent of the snake solver) &mdash; Gaussian blur
   &rarr; a single global Otsu threshold on grayscale intensity (the object
   is darker than its plain background, so this is enough to separate the
   two without tracing any boundary detail) &rarr; 8-connected component
   labeling &rarr; border-touching and noise-sized components are discarded,
   then survivors are merged by bounding-box proximity (`cluster_gap_px`) so
   a piece joined to the object only by something that fails to threshold as
   foreground -- e.g. a briefcase handle attached via reflective metal loops
   -- doesn't get dropped as unrelated background. The union of the winning
   cluster's bounding boxes, shrunk slightly, becomes a plain axis-aligned
   rectangle, resampled to `num_points` points. No manual seed point and no
   per-image threshold to hand-tune, but also no shape-hugging: a rectangle
   can't follow a box's slanted edges or a round object's curve, so the
   snake itself has to do the actual work of pulling the contour onto the
   true silhouette rather than just holding a shape that was already fit to
   it.
2. **The snake itself** (`snake.hpp`/`snake.cpp`) &mdash; the basic/greedy
   active contour: every point independently searches a small neighborhood
   each iteration for the position minimizing a weighted sum of continuity,
   curvature, and image energy, normalized to `[0, 1]` within its own
   candidate window. The full per-iteration history is returned so the
   frontend can animate convergence.

The three sample images are fixed (no path arguments): 

- a pumpkin (easy)
- a patterned storage box (medium)
- a briefcase (hard)

Each is a `config::ImageConfig<InitialContourParams, SnakeParams>`
instantiation in `config.hpp`. **Edit those** to change an image's defaults.

## Layout

Rust-flavored API: small `.hpp` files own the public surface, most
`.cpp` files are a page or two, errors are returned as `Result<T, E>` rather
than thrown, and the HTTP layer is built through a `Builder`.

```
include/week3/snake/   public headers (result.hpp, image.hpp, filters.hpp,
                        initial_contour.hpp, snake.hpp, config.hpp,
                        server.hpp, api.hpp)
src/                    matching .cpp files + main.cpp
web/                    the notebook frontend (vanilla HTML/CSS/JS, no
                        build step, no CDN dependencies) -- a global image
                        picker, a Run button, parameter sliders, and
                        play/pause/step/scrub controls that animate the
                        snake's saved per-iteration history
third_party/            vendored stb_image / stb_image_write, nlohmann/json,
                        and Mongoose (dual-licensed GPL-2.0 / commercial --
                        see third_party/mongoose/mongoose.h)
images/                 image1.jpg, image2.jpg, image3.jpg, and
                        provenance.md (source URLs + CC BY 2.0 attribution)
```

## Build & run

```sh
cmake -S . -B build -G Ninja
cmake --build build -j
./build/snake_notebook [listen_address]
# default: http://0.0.0.0:8080
# (the three sample images are always loaded from images/image1.jpg,
#  images/image2.jpg, and images/image3.jpg)
```

Then open the printed address in a browser. Pick an image at the top of the
page; every cell reacts to it. In cell 2, adjust the sliders (or leave them
at the per-image defaults from the config headers) and press **Run snake**
to solve, then **Play** or drag the frame slider to watch it converge.

`cmake --build build --target format` / `format-check` run clang-format over
every header and source file.

## Image licensing

All three sample images are from the
[Google Open Images Dataset](https://storage.googleapis.com/openimages/web/index.html)
(Flickr photos), licensed CC BY 2.0. Author, title, and source URL for each
are recorded in `images/provenance.md`.
