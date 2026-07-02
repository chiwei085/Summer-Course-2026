# week3 / color

An interactive, notebook-style demo of classic color-space operations,
implemented from scratch in C++20 (no OpenCV) and served over HTTP by a
vendored [Mongoose](https://github.com/cesanta/mongoose) server. Open the
page in a browser and it behaves like a live Jupyter notebook: every slider,
click, and dropdown calls back into the C++ backend, which does the actual
pixel math and returns JSON or PNG.

## What's inside

1. **RGB &rarr; Intensity** &mdash; average, lightness, and luminosity
   (BT.601 luma) grayscale conversions, computed pixel-by-pixel in
   `week3::color::rgb_to_intensity`.
2. **Histogram** &mdash; per-channel and intensity histograms over the
   full-resolution image.
3. **RGB cube &harr; HSV cone** &mdash; two linked visualizations of the same
   color, driven by `rgb_to_hsv` / `hsv_to_rgb`. The hue control is a
   circular dial (not a 0&ndash;360 linear slider) and there's a one-click
   demo that sweeps hue 350&deg; &rarr; 10&deg; the short way, through red,
   to exercise the 0&deg;/360&deg; wraparound explicitly.

## Layout

Header-heavy, Rust-flavored API: small `.hpp` files own the public surface,
most `.cpp` files are a page or two, errors are returned as `Result<T, E>`
rather than thrown, and the HTTP layer is built through a `Builder` rather
than mutable setters.

```
include/week3/color/   public headers (result.hpp, image.hpp, color.hpp,
                        histogram.hpp, server.hpp, api.hpp)
src/                    matching .cpp files + main.cpp
web/                    the notebook frontend (vanilla HTML/CSS/JS, no
                        build step, no CDN dependencies)
third_party/            vendored stb_image / stb_image_write, nlohmann/json,
                        and Mongoose (dual-licensed GPL-2.0 / commercial --
                        see third_party/mongoose/mongoose.h)
images/                 sample photo used as the default dataset
```

## Build & run

```sh
cmake -S . -B build -G Ninja
cmake --build build -j
./build/color_notebook [image_path] [listen_address]
# defaults: images/mortis.png, http://0.0.0.0:8080
```

Then open the printed address in a browser.

`cmake --build build --target format` / `format-check` run clang-format over
every header and source file.
