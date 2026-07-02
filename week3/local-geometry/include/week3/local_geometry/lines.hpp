#pragma once

#include <vector>

#include "week3/local_geometry/edges.hpp"

namespace week3::local_geometry
{

// One accumulator peak: a line in normal form x*cos(theta) + y*sin(theta) =
// rho, with `votes` edge pixels lying on it (within one accumulator cell).
struct HoughLine
{
    double rho{0.0};
    double theta{0.0};
    int votes{0};
};

struct HoughParams
{
    double theta_step_deg{1.0};
    double rho_step{1.0};
    int threshold{80};
    int max_lines{25};
    // Minimum angular separation (degrees) and rho separation (px) enforced
    // between kept peaks, so one thick line doesn't produce a cluster of
    // near-duplicate lines around its true accumulator peak.
    double min_theta_separation_deg{5.0};
    double min_rho_separation{10.0};
};

// Standard (rho, theta) Hough transform over every edge pixel in `edges`,
// followed by greedy peak picking with the separation rules in `params`.
[[nodiscard]] std::vector<HoughLine> hough_lines(const EdgeMap& edges,
                                                 const HoughParams& params);

// A finite piece of an infinite Hough line: the two endpoints found by
// projecting every edge pixel near the line onto it, sorting by position
// along the line, and splitting wherever consecutive points are farther
// apart than `max_gap`.
struct LineSegment
{
    double x1{0.0};
    double y1{0.0};
    double x2{0.0};
    double y2{0.0};
};

struct SegmentParams
{
    double max_point_distance{3.0};  // perpendicular distance to the line
    double max_gap{20.0};            // gap along the line that ends a run
    double min_length{15.0};
};

[[nodiscard]] std::vector<LineSegment> extract_segments(
    const EdgeMap& edges, const std::vector<HoughLine>& lines,
    const SegmentParams& params);

}  // namespace week3::local_geometry
