#include "week3/snake/snake.hpp"

#include <algorithm>
#include <cmath>

namespace week3::snake
{
namespace
{

[[maybe_unused]] double sample_bilinear(const GrayImage& field, double x,
                                        double y) {
    const int x0 =
        std::clamp(static_cast<int>(std::floor(x)), 0, field.size.width - 1);
    const int y0 =
        std::clamp(static_cast<int>(std::floor(y)), 0, field.size.height - 1);
    const int x1 = std::min(x0 + 1, field.size.width - 1);
    const int y1 = std::min(y0 + 1, field.size.height - 1);
    const double fx = std::clamp(x - x0, 0.0, 1.0);
    const double fy = std::clamp(y - y0, 0.0, 1.0);
    const double top = field.at(x0, y0) * (1.0 - fx) + field.at(x1, y0) * fx;
    const double bottom = field.at(x0, y1) * (1.0 - fx) + field.at(x1, y1) * fx;
    return top * (1.0 - fy) + bottom * fy;
}

[[maybe_unused]] double dist(Point2d a, Point2d b) {
    return std::hypot(a.x - b.x, a.y - b.y);
}

}  // namespace

SnakeRun run_snake(const GrayImage& gray,
                   const std::vector<Point2d>& initial_points,
                   SnakeParams params) {
    // External energy field: gradient magnitude of the blurred image.
    // Sample it with `sample_bilinear`, since contour points are not on the
    // integer pixel grid.
    const GrayImage blurred = gaussian_blur(gray, params.energy_sigma);
    [[maybe_unused]] const GrayImage magnitude =
        sobel_gradients(blurred).magnitude;

    SnakeRun run;
    run.history.push_back(initial_points);

    const int n = static_cast<int>(initial_points.size());
    if (n < 3) return run;

    [[maybe_unused]] const double max_x =
        static_cast<double>(gray.size.width - 1);
    [[maybe_unused]] const double max_y =
        static_cast<double>(gray.size.height - 1);
    std::vector<Point2d> points = initial_points;

    for (int iter = 0; iter < params.iterations; ++iter) {
        // TODO: one greedy update pass over every point of the closed
        // contour (Williams & Shah, 1992). The energy terms and their
        // weights are specified in snake.hpp. Update `points` and append
        // the new contour to run.history, one entry per iteration, which
        // the frontend animates.
        //
        // Placeholder: the contour never moves.
        run.history.push_back(points);
    }
    return run;
}

}  // namespace week3::snake
