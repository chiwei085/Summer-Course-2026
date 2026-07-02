#include <week3/calibration/calibration.hpp>

#include <algorithm>
#include <array>
#include <cmath>

namespace week3
{
namespace
{

using linalg::Mat3;
using linalg::Matrix;
using linalg::Vec2;
using linalg::Vec3;

// Reshapes the 9-vector solution of the homography DLT system into a 3x3
// matrix, dividing through by the last entry so h(2,2) == 1.
Mat3 homography_from_vector(const std::vector<double>& h) {
    Mat3 out{};
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t col = 0; col < 3; ++col) {
            out(row, col) = h[row * 3 + col] / h[8];
        }
    }
    return out;
}

// A similarity transform (isotropic scale + translation) together with the
// points it produces when applied to the input.
struct SimilarityNormalization
{
    Mat3 transform;
    std::vector<Vec2> points;
};

// Hartley normalization: recenters `points` on their centroid and rescales
// them so the average distance to the origin is sqrt(2). Solving the
// homography DLT system in this normalized frame (rather than raw pixel/
// board coordinates) keeps the linear system well-conditioned.
SimilarityNormalization normalize_points(std::span<const Vec2> points) {
    Vec2 mean{};
    for (const Vec2 point : points) {
        mean.x += point.x;
        mean.y += point.y;
    }
    mean.x /= static_cast<double>(points.size());
    mean.y /= static_cast<double>(points.size());

    double mean_distance = 0.0;
    for (const Vec2 point : points) {
        mean_distance += std::hypot(point.x - mean.x, point.y - mean.y);
    }
    mean_distance /= static_cast<double>(points.size());
    const double scale = std::sqrt(2.0) / mean_distance;

    Mat3 transform = linalg::identity3();
    transform(0, 0) = scale;
    transform(1, 1) = scale;
    transform(0, 2) = -scale * mean.x;
    transform(1, 2) = -scale * mean.y;

    std::vector<Vec2> normalized;
    normalized.reserve(points.size());
    for (const Vec2 point : points) {
        normalized.push_back({
            .x = scale * (point.x - mean.x),
            .y = scale * (point.y - mean.y),
        });
    }
    return {.transform = transform, .points = std::move(normalized)};
}

// Estimates the homography that maps board-plane points to pixel
// coordinates for a single image, via the normalized Direct Linear
// Transform (DLT): build a 2N x 9 system from point correspondences, solve
// it as the eigenvector of smallest eigenvalue of A^T A, then undo the
// point normalization to recover the homography in pixel coordinates.
Result<Mat3, Error> estimate_homography(const BoardSpec& board,
                                        const ImageObservations& image) {
    std::vector<Vec2> world_points;
    std::vector<Vec2> pixel_points;
    world_points.reserve(image.corners.size());
    pixel_points.reserve(image.corners.size());
    for (const auto& corner : image.corners) {
        world_points.push_back(board_point(board, corner));
        pixel_points.push_back(corner.pixel);
    }

    const auto world_norm = normalize_points(world_points);
    const auto pixel_norm = normalize_points(pixel_points);

    // Each correspondence (world -> pixel) contributes two rows enforcing
    // pixel x homography*world (cross product form of the DLT constraint).
    auto system = Matrix::zero(image.corners.size() * 2, 9);
    for (std::size_t i = 0; i < image.corners.size(); ++i) {
        const Vec2 world = world_norm.points[i];
        const Vec2 pixel = pixel_norm.points[i];
        const std::size_t row = i * 2;

        system(row, 0) = -world.x;
        system(row, 1) = -world.y;
        system(row, 2) = -1.0;
        system(row, 6) = pixel.x * world.x;
        system(row, 7) = pixel.x * world.y;
        system(row, 8) = pixel.x;

        system(row + 1, 3) = -world.x;
        system(row + 1, 4) = -world.y;
        system(row + 1, 5) = -1.0;
        system(row + 1, 6) = pixel.y * world.x;
        system(row + 1, 7) = pixel.y * world.y;
        system(row + 1, 8) = pixel.y;
    }

    auto eigenvector = linalg::smallest_eigenvector_symmetric(
        linalg::transpose_multiply_self(system));
    if (eigenvector.is_err()) {
        return Result<Mat3, Error>::err(eigenvector.error());
    }
    if (linalg::nearly_zero(eigenvector.value()[8])) {
        return Result<Mat3, Error>::err(
            {.message = "homography solve produced a degenerate scale"});
    }
    const Mat3 normalized_homography =
        homography_from_vector(eigenvector.value());
    // Undo the Hartley normalization: H = T_pixel^-1 * H_normalized * T_world.
    Mat3 homography = linalg::inverse(pixel_norm.transform) *
                      (normalized_homography * world_norm.transform);
    for (double& value : homography.values) {
        value /= homography(2, 2);
    }
    return Result<Mat3, Error>::ok(homography);
}

// Builds the row v_ij of Zhang's linear system relating a homography's
// columns h_i, h_j to the symmetric matrix B = K^-T K^-1 (the image of the
// absolute conic), packed as [B11, B12, B22, B13, B23, B33].
std::array<double, 6> v_ij(const Mat3& h, int i, int j) {
    return {
        h(0, i) * h(0, j),
        h(0, i) * h(1, j) + h(1, i) * h(0, j),
        h(1, i) * h(1, j),
        h(2, i) * h(0, j) + h(0, i) * h(2, j),
        h(2, i) * h(1, j) + h(1, i) * h(2, j),
        h(2, i) * h(2, j),
    };
}

// Recovers the shared camera intrinsics from a set of per-view
// homographies. Each homography's columns being orthonormal in the camera
// frame (h1 ⊥ h2, |h1| = |h2|) gives two linear constraints on B = K^-T K^-1
// per view; stacking them across all views and solving via the same
// smallest-eigenvector trick as the homography DLT yields B, which is then
// decomposed in closed form (Zhang, Appendix B) into fx, fy, cx, cy, skew.
Result<Intrinsics, Error> estimate_intrinsics(
    const std::vector<Mat3>& homographies) {
    auto system = Matrix::zero(homographies.size() * 2, 6);
    for (std::size_t row = 0; row < homographies.size(); ++row) {
        const auto v12 = v_ij(homographies[row], 0, 1);
        const auto v11 = v_ij(homographies[row], 0, 0);
        const auto v22 = v_ij(homographies[row], 1, 1);
        for (std::size_t col = 0; col < 6; ++col) {
            system(2 * row, col) = v12[col];
            system(2 * row + 1, col) = v11[col] - v22[col];
        }
    }

    auto b = linalg::smallest_eigenvector_symmetric(
        linalg::transpose_multiply_self(system));
    if (b.is_err()) {
        return Result<Intrinsics, Error>::err(b.error());
    }

    // b holds the packed entries of B: [B11, B12, B22, B13, B23, B33].
    const double b11 = b.value()[0];
    const double b12 = b.value()[1];
    const double b22 = b.value()[2];
    const double b13 = b.value()[3];
    const double b23 = b.value()[4];
    const double b33 = b.value()[5];
    const double denominator = b11 * b22 - b12 * b12;
    if (linalg::nearly_zero(denominator) || linalg::nearly_zero(b11)) {
        return Result<Intrinsics, Error>::err(
            {.message = "intrinsic solve produced a degenerate conic"});
    }

    const double cy = (b12 * b13 - b11 * b23) / denominator;
    const double lambda =
        b33 - (b13 * b13 + cy * (b12 * b13 - b11 * b23)) / b11;
    const double fx_square = lambda / b11;
    const double fy_square = lambda * b11 / denominator;
    if (fx_square <= 0.0 || fy_square <= 0.0) {
        return Result<Intrinsics, Error>::err(
            {.message = "intrinsic solve produced a non-positive focal "
                        "length"});
    }

    const double fx = std::sqrt(fx_square);
    const double fy = std::sqrt(fy_square);
    const double skew = -b12 * fx * fx * fy / lambda;
    const double cx = skew * cy / fy - b13 * fx * fx / lambda;
    return Result<Intrinsics, Error>::ok({
        .fx = fx,
        .fy = fy,
        .cx = cx,
        .cy = cy,
        .skew = skew,
    });
}

// Projects a board-plane point (z = 0 in board coordinates) into pixel
// coordinates using the given pose and intrinsics: transform to the camera
// frame, perspective-divide, then apply K.
Vec2 project(const Intrinsics& intrinsics, const CameraPose& pose, Vec2 world) {
    const Vec3 camera =
        pose.rotation * Vec3{.x = world.x, .y = world.y, .z = 0.0} +
        pose.translation;
    const double x = camera.x / camera.z;
    const double y = camera.y / camera.z;
    return {
        .x = intrinsics.fx * x + intrinsics.skew * y + intrinsics.cx,
        .y = intrinsics.fy * y + intrinsics.cy,
    };
}

// Decomposes a homography into a camera pose (rotation + translation) given
// known intrinsics, following Zhang's method: K^-1 H = [r1 r2 t] up to
// scale, so r1/r2 are recovered from the first two columns (Gram-Schmidt
// orthonormalized to correct for estimation noise) and r3 completes a
// right-handed basis via their cross product.
CameraPose estimate_pose(const Intrinsics& intrinsics, const Mat3& homography) {
    const Mat3 inv_k = linalg::inverse(intrinsics.matrix());
    const Vec3 h1 = linalg::column(homography, 0);
    const Vec3 h2 = linalg::column(homography, 1);
    const Vec3 h3 = linalg::column(homography, 2);
    const Vec3 inv_h1 = inv_k * h1;
    const Vec3 inv_h2 = inv_k * h2;
    // H is only known up to scale; normalize using the average column norm
    // so r1/r2 come out unit length.
    const double scale = 2.0 / (linalg::norm(inv_h1) + linalg::norm(inv_h2));

    Vec3 r1 = linalg::normalized(scale * inv_h1);
    Vec3 r2_raw = scale * inv_h2;
    Vec3 r2 = linalg::normalized(r2_raw - linalg::dot(r1, r2_raw) * r1);
    Vec3 r3 = linalg::cross(r1, r2);
    Vec3 t = scale * (inv_k * h3);

    // The homography's overall sign is ambiguous, so t.z < 0 would place
    // the board behind the camera; flip r1, r2 and t to correct it. r3 is
    // recomputed rather than also negated: cross(-r1, -r2) == cross(r1, r2),
    // so the recompute is what keeps [r1 r2 r3] a right-handed rotation.
    if (t.z < 0.0) {
        r1 = -1.0 * r1;
        r2 = -1.0 * r2;
        r3 = linalg::cross(r1, r2);
        t = -1.0 * t;
    }

    Mat3 rotation{};
    linalg::set_column(rotation, 0, r1);
    linalg::set_column(rotation, 1, r2);
    linalg::set_column(rotation, 2, r3);
    return {.rotation = rotation, .translation = t};
}

// Reprojects every detected corner in `image` using the given intrinsics
// and pose, and returns the RMS pixel distance to the observed corners.
double view_rms_error(const BoardSpec& board, const ImageObservations& image,
                      const Intrinsics& intrinsics, const CameraPose& pose) {
    double squared_sum = 0.0;
    for (const auto& corner : image.corners) {
        const Vec2 predicted =
            project(intrinsics, pose, board_point(board, corner));
        const double dx = predicted.x - corner.pixel.x;
        const double dy = predicted.y - corner.pixel.y;
        squared_sum += dx * dx + dy * dy;
    }
    return std::sqrt(squared_sum / static_cast<double>(image.corners.size()));
}

// --- Nonlinear refinement -------------------------------------------------
//
// The closed-form estimates above solve each stage (homography, intrinsics,
// pose) independently and linearly, which does not directly minimize
// reprojection error. The functions below take that closed-form solution as
// an initial guess and refine it with Levenberg-Marquardt, jointly
// optimizing the shared intrinsics and all per-view poses against total
// squared reprojection error, without changing the camera model itself
// (still a distortion-free pinhole model).

// Skew-symmetric "cross-product matrix" of `v`, i.e. the matrix K such that
// K * x == cross(v, x) for any x.
Mat3 skew_symmetric(Vec3 v) {
    Mat3 out{};
    out(0, 1) = -v.z;
    out(0, 2) = v.y;
    out(1, 0) = v.z;
    out(1, 2) = -v.x;
    out(2, 0) = -v.y;
    out(2, 1) = v.x;
    return out;
}

// Rodrigues' rotation formula: converts an axis-angle vector (direction =
// rotation axis, magnitude = rotation angle in radians) into a rotation
// matrix. Used as the exponential map for a minimal, singularity-free-near-
// zero rotation parameterization during optimization.
Mat3 rotation_from_axis_angle(Vec3 r) {
    const double theta = linalg::norm(r);
    Mat3 out = linalg::identity3();
    if (theta < 1e-12) {
        return out;
    }
    const Mat3 k = skew_symmetric(r / theta);
    const Mat3 k2 = k * k;
    const double sin_theta = std::sin(theta);
    const double cos_term = 1.0 - std::cos(theta);
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t col = 0; col < 3; ++col) {
            out(row, col) += sin_theta * k(row, col) + cos_term * k2(row, col);
        }
    }
    return out;
}

// Inverse of rotation_from_axis_angle (the logarithm map): recovers the
// axis-angle vector for a rotation matrix, used to seed optimization
// parameters from the closed-form pose estimate.
Vec3 axis_angle_from_rotation(const Mat3& r) {
    const double trace = r(0, 0) + r(1, 1) + r(2, 2);
    const double cos_theta = std::clamp(0.5 * (trace - 1.0), -1.0, 1.0);
    const double theta = std::acos(cos_theta);
    if (theta < 1e-12) {
        return {};
    }
    const double scale = theta / (2.0 * std::sin(theta));
    return {
        .x = scale * (r(2, 1) - r(1, 2)),
        .y = scale * (r(0, 2) - r(2, 0)),
        .z = scale * (r(1, 0) - r(0, 1)),
    };
}

// The joint set of camera intrinsics and per-view poses being optimized.
struct CalibrationParameters
{
    Intrinsics intrinsics;
    std::vector<CameraPose> poses;
};

// Packs `params` into a flat vector: [fx, fy, cx, cy, skew, then per view
// (rx, ry, rz, tx, ty, tz)]. This is the layout the optimizer works in.
std::vector<double> pack_parameters(const CalibrationParameters& params) {
    std::vector<double> packed;
    packed.reserve(5 + params.poses.size() * 6);
    packed.insert(packed.end(), {params.intrinsics.fx, params.intrinsics.fy,
                                 params.intrinsics.cx, params.intrinsics.cy,
                                 params.intrinsics.skew});
    for (const CameraPose& pose : params.poses) {
        const Vec3 r = axis_angle_from_rotation(pose.rotation);
        packed.insert(packed.end(), {r.x, r.y, r.z, pose.translation.x,
                                     pose.translation.y, pose.translation.z});
    }
    return packed;
}

// Inverse of pack_parameters.
CalibrationParameters unpack_parameters(const std::vector<double>& packed,
                                        std::size_t view_count) {
    CalibrationParameters params;
    params.intrinsics = {
        .fx = packed[0],
        .fy = packed[1],
        .cx = packed[2],
        .cy = packed[3],
        .skew = packed[4],
    };
    params.poses.reserve(view_count);
    for (std::size_t i = 0; i < view_count; ++i) {
        const std::size_t base = 5 + i * 6;
        const Vec3 r{
            .x = packed[base], .y = packed[base + 1], .z = packed[base + 2]};
        const Vec3 t{.x = packed[base + 3],
                     .y = packed[base + 4],
                     .z = packed[base + 5]};
        params.poses.push_back(
            {.rotation = rotation_from_axis_angle(r), .translation = t});
    }
    return params;
}

// Flattened per-corner (dx, dy) reprojection residuals over every view, in
// the same [image][corner] order as `dataset.images`.
std::vector<double> compute_residuals(const CalibrationDataset& dataset,
                                      const CalibrationParameters& params) {
    std::vector<double> residuals;
    for (std::size_t i = 0; i < dataset.images.size(); ++i) {
        const ImageObservations& image = dataset.images[i];
        for (const auto& corner : image.corners) {
            const Vec2 predicted = project(params.intrinsics, params.poses[i],
                                           board_point(dataset.board, corner));
            residuals.push_back(predicted.x - corner.pixel.x);
            residuals.push_back(predicted.y - corner.pixel.y);
        }
    }
    return residuals;
}

double sum_of_squares(const std::vector<double>& values) {
    double sum = 0.0;
    for (const double value : values) {
        sum += value * value;
    }
    return sum;
}

// Central-difference numerical Jacobian of compute_residuals with respect
// to the packed parameter vector. The problem is small enough (a handful of
// intrinsics plus 6 parameters per view) that finite differences are simple
// and fast enough, avoiding a hand-derived analytic Jacobian.
Matrix numerical_jacobian(const CalibrationDataset& dataset,
                          const std::vector<double>& packed,
                          std::size_t view_count,
                          const std::vector<double>& residuals_at_packed) {
    constexpr double kStep = 1e-6;
    Matrix jacobian = Matrix::zero(residuals_at_packed.size(), packed.size());
    for (std::size_t p = 0; p < packed.size(); ++p) {
        std::vector<double> plus = packed;
        std::vector<double> minus = packed;
        plus[p] += kStep;
        minus[p] -= kStep;
        const auto plus_residuals =
            compute_residuals(dataset, unpack_parameters(plus, view_count));
        const auto minus_residuals =
            compute_residuals(dataset, unpack_parameters(minus, view_count));
        for (std::size_t row = 0; row < residuals_at_packed.size(); ++row) {
            jacobian(row, p) =
                (plus_residuals[row] - minus_residuals[row]) / (2.0 * kStep);
        }
    }
    return jacobian;
}

// Refines `initial` with Levenberg-Marquardt to minimize total squared
// reprojection error over `dataset`. Best-effort: if a damped normal-
// equation solve fails or no step improves the cost, the search stops and
// the best parameters found so far (at worst, `initial`) are returned, so
// this never turns a successful closed-form calibration into a failure.
CalibrationParameters refine_calibration(const CalibrationDataset& dataset,
                                         const CalibrationParameters& initial) {
    const std::size_t view_count = initial.poses.size();
    std::vector<double> packed = pack_parameters(initial);
    std::vector<double> residuals = compute_residuals(dataset, initial);
    double cost = sum_of_squares(residuals);

    double lambda = 1e-3;
    constexpr int kMaxIterations = 50;
    constexpr int kMaxAttemptsPerIteration = 10;
    constexpr double kCostImprovementTolerance = 1e-12;

    for (int iteration = 0; iteration < kMaxIterations; ++iteration) {
        const Matrix jacobian =
            numerical_jacobian(dataset, packed, view_count, residuals);
        const Matrix jt_j = linalg::transpose_multiply_self(jacobian);

        std::vector<double> jt_r(packed.size(), 0.0);
        for (std::size_t row = 0; row < jacobian.rows; ++row) {
            for (std::size_t col = 0; col < jacobian.cols; ++col) {
                jt_r[col] += jacobian(row, col) * residuals[row];
            }
        }

        bool step_accepted = false;
        double accepted_improvement = 0.0;
        for (int attempt = 0; attempt < kMaxAttemptsPerIteration; ++attempt) {
            Matrix damped = jt_j;
            for (std::size_t d = 0; d < damped.rows; ++d) {
                damped(d, d) += lambda * jt_j(d, d);
            }
            std::vector<double> rhs(jt_r.size());
            for (std::size_t i = 0; i < rhs.size(); ++i) {
                rhs[i] = -jt_r[i];
            }
            auto delta = linalg::solve_spd(damped, rhs);
            if (delta.is_err()) {
                lambda *= 10.0;
                continue;
            }

            std::vector<double> candidate = packed;
            for (std::size_t i = 0; i < candidate.size(); ++i) {
                candidate[i] += delta.value()[i];
            }
            const auto candidate_params =
                unpack_parameters(candidate, view_count);
            auto candidate_residuals =
                compute_residuals(dataset, candidate_params);
            const double candidate_cost = sum_of_squares(candidate_residuals);

            if (candidate_cost < cost) {
                accepted_improvement = cost - candidate_cost;
                packed = std::move(candidate);
                residuals = std::move(candidate_residuals);
                cost = candidate_cost;
                lambda *= 0.5;
                step_accepted = true;
                break;
            }
            lambda *= 10.0;
        }
        if (!step_accepted ||
            accepted_improvement < kCostImprovementTolerance) {
            break;
        }
    }

    return unpack_parameters(packed, view_count);
}

}  // namespace

linalg::Mat3 Intrinsics::matrix() const {
    linalg::Mat3 out{};
    out(0, 0) = fx;
    out(0, 1) = skew;
    out(0, 2) = cx;
    out(1, 1) = fy;
    out(1, 2) = cy;
    out(2, 2) = 1.0;
    return out;
}

// Entry point: runs the full Zhang calibration pipeline over `dataset` —
// per-view homography estimation, shared intrinsic recovery, then per-view
// pose and reprojection-error computation — and aggregates the results.
Result<CalibrationReport, Error> calibrate_camera(
    const CalibrationDataset& dataset) {
    std::vector<Mat3> homographies;
    homographies.reserve(dataset.images.size());
    for (const auto& image : dataset.images) {
        auto homography = estimate_homography(dataset.board, image);
        if (homography.is_err()) {
            return Result<CalibrationReport, Error>::err(
                {.message =
                     image.image_name + ": " + homography.error().message});
        }
        homographies.push_back(homography.value());
    }

    auto intrinsics = estimate_intrinsics(homographies);
    if (intrinsics.is_err()) {
        return Result<CalibrationReport, Error>::err(intrinsics.error());
    }

    CalibrationParameters params{.intrinsics = intrinsics.value(), .poses = {}};
    params.poses.reserve(dataset.images.size());
    for (std::size_t i = 0; i < dataset.images.size(); ++i) {
        params.poses.push_back(
            estimate_pose(intrinsics.value(), homographies[i]));
    }

    // Nonlinear refinement: jointly optimizes the shared intrinsics and all
    // per-view poses against total squared reprojection error, improving on
    // the closed-form linear estimate above (which does not itself minimize
    // reprojection error) without changing the pinhole camera model.
    params = refine_calibration(dataset, params);

    std::vector<ViewCalibration> views;
    views.reserve(dataset.images.size());
    double squared_sum = 0.0;
    int corner_count = 0;
    for (std::size_t i = 0; i < dataset.images.size(); ++i) {
        const double rms = view_rms_error(dataset.board, dataset.images[i],
                                          params.intrinsics, params.poses[i]);
        squared_sum +=
            rms * rms * static_cast<double>(dataset.images[i].corners.size());
        corner_count += static_cast<int>(dataset.images[i].corners.size());
        views.push_back({
            .image_name = dataset.images[i].image_name,
            .homography = homographies[i],
            .pose = params.poses[i],
            .rms_error_px = rms,
        });
    }

    // Overall RMS is computed over all corners across all views (not an
    // average of per-view RMS values), so views with more corners are
    // weighted proportionally more.
    return Result<CalibrationReport, Error>::ok({
        .intrinsics = params.intrinsics,
        .views = std::move(views),
        .overall_rms_error_px =
            std::sqrt(squared_sum / static_cast<double>(corner_count)),
    });
}

}  // namespace week3
