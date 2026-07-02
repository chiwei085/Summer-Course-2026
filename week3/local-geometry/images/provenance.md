# Local Geometry Data Provenance

This lab uses two downloaded sample images in addition to
`images/scissors.png` (already part of the repo, same treatment as
`week3/color/images/mortis.png` -- no separate license file). All images and
their license files live together in this directory.

## `images/building.jpg`

Downloaded from the OpenCV sample data repository:

https://raw.githubusercontent.com/opencv/opencv/4.x/samples/data/building.jpg

OpenCV is licensed under Apache License 2.0. A copy of that license is stored
in `OPENCV_LICENSE.txt` (same file already vendored by
`week3/calibration/data/OPENCV_LICENSE.txt`).

Used for corner detection: it has strong rectilinear structure (windows,
ledges, roofline) that produces clean Harris corner responses.

## `images/solidWhiteRight.jpg`

Downloaded from the Udacity "CarND-LaneLines-P1" sample test images:

https://raw.githubusercontent.com/udacity/CarND-LaneLines-P1/master/test_images/solidWhiteRight.jpg

The repository (https://github.com/udacity/CarND-LaneLines-P1) has a
`LICENSE` file at its root: the MIT License, Copyright (c) 2016-2019 Udacity,
Inc. A copy of that license is stored in `CARND_LANELINES_LICENSE.txt`.

Used for line detection: it's a forward-facing dashcam frame with clear
straight lane markings, the canonical input for a Hough-transform line
detector.

## Provenance of the files themselves

Both images and the Udacity license file were fetched directly with `curl`
from the URLs above and are stored verbatim (no re-encoding).
