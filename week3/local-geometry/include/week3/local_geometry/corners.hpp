#pragma once

#include <vector>

#include "week3/local_geometry/gradient.hpp"

namespace week3::local_geometry
{

// The 2x2 structure tensor M = [[Ixx, Ixy], [Ixy, Iyy]] summed over a
// window, evaluated at every pixel. Its eigenvalues describe how much the
// local image gradient varies in each direction: two large eigenvalues mean
// a corner, one large and one small mean an edge, two small mean a flat
// region.
struct StructureTensor
{
    GrayImage ixx;
    GrayImage iyy;
    GrayImage ixy;
};

[[nodiscard]] StructureTensor structure_tensor(const Gradients& gradients,
                                               int window_radius);

// Harris corner response R = det(M) - k * trace(M)^2 at every pixel, an
// eigenvalue-free proxy for "both structure-tensor eigenvalues are large".
[[nodiscard]] GrayImage harris_response(const StructureTensor& tensor,
                                        double k);

struct Corner
{
    int x{0};
    int y{0};
    double response{0.0};
};

// Keeps only pixels whose response clears `threshold` and is the strict
// maximum within `nms_radius` of itself, then returns them sorted by
// descending response.
[[nodiscard]] std::vector<Corner> detect_corners(const GrayImage& response,
                                                 double threshold,
                                                 int nms_radius);

}  // namespace week3::local_geometry
