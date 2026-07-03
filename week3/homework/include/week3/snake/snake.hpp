#pragma once

#include <vector>

#include "week3/snake/filters.hpp"
#include "week3/snake/image.hpp"

namespace week3::snake
{

// Parameters for the basic greedy snake (Williams & Shah, 1992): at every
// iteration, every contour point independently searches a small
// neighborhood for the position that minimizes a weighted sum of internal
// (shape) energy and external (image) energy, and jumps straight there.
// There's no linear system to solve, which keeps the algorithm easy to
// animate frame-by-frame -- it's the "basic version" the assignment asks
// for, as opposed to the original variational/matrix-inversion formulation.
struct SnakeParams
{
    // Continuity weight: penalizes a point's distance to its neighbors
    // deviating from the contour's current average point spacing. Keeps
    // points roughly evenly spaced instead of bunching up.
    double alpha{0.6};

    // Curvature weight: penalizes |p[i-1] - 2*p[i] + p[i+1]|^2, the
    // discrete second derivative. Keeps the contour smooth.
    double beta{0.4};

    // External-energy weight: how strongly points are pulled toward high
    // image-gradient magnitude (edges).
    double gamma{1.2};

    // Gaussian blur applied to the image before computing the gradient
    // magnitude used as external energy. Larger sigma widens each edge's
    // "basin of attraction" so a point doesn't need to already be within a
    // pixel or two of the true boundary to feel it -- distinct from (and
    // usually larger than) `InitialContourParams::blur_sigma`.
    double energy_sigma{2.5};

    // Points search a (2*search_radius+1)^2 neighborhood around their
    // current position each iteration.
    int search_radius{2};

    int iterations{150};
};

// One contour shape at a point in time. `history[0]` is the initial contour
// handed in; every entry after that is the state after one greedy update
// pass over every point.
struct SnakeRun
{
    std::vector<std::vector<Point2d>> history;
};

[[nodiscard]] SnakeRun run_snake(const GrayImage& gray,
                                 const std::vector<Point2d>& initial_points,
                                 SnakeParams params);

}  // namespace week3::snake
