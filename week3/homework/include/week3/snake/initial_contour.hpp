#pragma once

#include <vector>

#include "week3/snake/filters.hpp"
#include "week3/snake/image.hpp"

namespace week3::snake
{

// Tunable knobs for automatic initial-contour placement. Deliberately kept
// crude: this only has to find roughly where the object is, not trace its
// shape. The snake is what's being taught here, so it needs real work to do
// -- a starting contour that's already close to the true silhouette would
// make the snake's energy terms nearly irrelevant to the outcome. A bounding
// rectangle (rather than an inscribed ellipse) keeps that starting distance
// short everywhere the object actually reaches its own bounding box (most of
// a box's or briefcase's outline touches its bbox at some point), so the
// greedy per-point search below only ever has to shrink a short distance
// inward onto a nearby real edge, not cross a wide gradient-free gap -- the
// latter is outside what a plain snake (no balloon force / GVF) can recover
// from.
struct InitialContourParams
{
    // Gaussian blur applied before thresholding, in pixels.
    double blur_sigma{1.5};

    // The detected bounding box is scaled by this factor (about its center)
    // before resampling. Kept close to 1.0: the box already touches the
    // object at its extremes, so shrinking much would pull the start inside
    // the object on those sides.
    double shrink_factor{0.97};

    // After border-touching and noise-sized components are discarded, the
    // survivors are clustered by bounding-box proximity (boxes within this
    // many pixels of each other join the same cluster) and the cluster with
    // the most total pixels is treated as "the object", using the union of
    // its members' bounding boxes. This is what keeps a piece connected to
    // the object only by something that fails to threshold as foreground
    // (e.g. a briefcase handle joined to the case by reflective metal
    // loops) from being dropped as if it were unrelated background.
    int cluster_gap_px{40};

    // Number of points sampled uniformly around the bounding rectangle.
    int num_points{80};
};

// A closed polygon plus the axis-aligned bounding box of the connected
// component it was fit to (returned mainly for diagnostics/visualization).
struct InitialContour
{
    std::vector<Point2d> points;
    double bbox_x0{0.0};
    double bbox_y0{0.0};
    double bbox_x1{0.0};
    double bbox_y1{0.0};
};

// Finds a rough automatic starting contour with no manual seed point:
//   1. grayscale -> Gaussian blur
//   2. Otsu's method picks a global intensity threshold separating the
//      (plain, bright) background from the (darker) object -- a single
//      binary mask, not an edge map
//   3. connected-component labeling finds candidate blobs; border-touching
//      ones (background/frame) and tiny specks are discarded
//   4. the largest surviving component's bounding box, shrunk slightly, is
//      resampled into `num_points` points evenly spaced around its
//      perimeter
// The result is intentionally only a coarse approximation of the object's
// silhouette -- a rectangle can't follow a box's slanted edges or a
// briefcase handle's loop -- so the snake actually has to deform it onto
// the true boundary.
[[nodiscard]] InitialContour find_initial_contour(const GrayImage& gray,
                                                  InitialContourParams params);

}  // namespace week3::snake
