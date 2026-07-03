#pragma once

#include "week3/snake/initial_contour.hpp"
#include "week3/snake/snake.hpp"

// A single struct template holds one sample image's full tuning. Each image
// instantiates it with its own `InitialContourParams`/`SnakeParams` (C++20
// allows literal aggregates as non-type template parameters) instead of
// getting a whole separate header -- the three images below differ only in
// the values they pass in, not in shape.
namespace week3::snake::config
{

template <InitialContourParams Init, SnakeParams Snake>
struct ImageConfig
{
    static constexpr InitialContourParams init = Init;
    static constexpr SnakeParams snake = Snake;
};

// image 1 -- a pumpkin on a plain white background. The initial contour is
// just the object's bounding rectangle (see `find_initial_contour`), so even
// this near-round object starts with the four corners sitting well outside
// the true silhouette; the snake has to pull the boundary in onto the round
// edge, not just hold a shape that was already fit to it.
inline constexpr const char* kImage1Path = "images/image1.jpg";
using Image1 = ImageConfig<InitialContourParams{.blur_sigma = 1.0,
                                                .shrink_factor = 0.97,
                                                .cluster_gap_px = 40,
                                                .num_points = 80},
                           SnakeParams{.alpha = 0.5,
                                       .beta = 0.5,
                                       .gamma = 1.3,
                                       .energy_sigma = 2.0,
                                       .search_radius = 4,
                                       .iterations = 150}>;

// image 2 -- a patterned storage box on a plain white background, shown at
// an angle so its outline is a hexagon rather than a simple rectangle. Its
// bounding rectangle touches the true outline at only two opposite corners;
// everywhere else the snake has to shrink the boundary inward onto the
// slanted edges using image energy alone.
inline constexpr const char* kImage2Path = "images/image2.jpg";
using Image2 = ImageConfig<InitialContourParams{.blur_sigma = 1.2,
                                                .shrink_factor = 0.97,
                                                .cluster_gap_px = 40,
                                                .num_points = 90},
                           SnakeParams{.alpha = 0.6,
                                       .beta = 0.5,
                                       .gamma = 1.5,
                                       .energy_sigma = 2.5,
                                       .search_radius = 4,
                                       .iterations = 200}>;

// image 3 -- a briefcase (with an iPad screen printed on the front flap) on
// a plain white background. Its handle thresholds as its own component,
// separated from the case body by the reflective metal loops joining them
// (those go bright, not dark, so they don't survive the foreground
// threshold) -- bounding-box clustering (`cluster_gap_px`) is what folds the
// handle's extent back into the object's bounding box, since a rectangle
// that stopped at the case alone would put the handle completely outside
// the snake's reach. The handle's loop shape, and the printed screen
// graphic's internal high-contrast edges, are still real challenges for the
// snake itself.
inline constexpr const char* kImage3Path = "images/image3.jpg";
using Image3 = ImageConfig<InitialContourParams{.blur_sigma = 1.2,
                                                .shrink_factor = 0.97,
                                                .cluster_gap_px = 40,
                                                .num_points = 90},
                           SnakeParams{.alpha = 0.8,
                                       .beta = 0.6,
                                       .gamma = 1.8,
                                       .energy_sigma = 3.0,
                                       .search_radius = 4,
                                       .iterations = 250}>;

}  // namespace week3::snake::config
