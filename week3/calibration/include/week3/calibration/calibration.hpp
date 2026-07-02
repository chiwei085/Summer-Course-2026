#pragma once

#include <week3/calibration/dataset.hpp>
#include <week3/calibration/linalg.hpp>
#include <week3/calibration/result.hpp>

#include <vector>

namespace week3
{

// Pinhole camera intrinsic parameters, i.e. the entries of the calibration
// matrix K:
//   | fx  skew  cx |
//   | 0    fy   cy |
//   | 0    0    1  |
// fx/fy are the focal lengths in pixels, cx/cy the principal point, and skew
// accounts for non-perpendicular pixel axes (usually ~0 for real cameras).
struct Intrinsics
{
    double fx{0.0};
    double fy{0.0};
    double cx{0.0};
    double cy{0.0};
    double skew{0.0};

    // Assembles K from the fields above.
    [[nodiscard]] linalg::Mat3 matrix() const;
};

// Extrinsic parameters of one calibration-board view: the rotation and
// translation that map board-plane coordinates into the camera frame.
struct CameraPose
{
    linalg::Mat3 rotation;
    linalg::Vec3 translation;
};

// Per-image calibration result: the homography that maps the board plane to
// pixel coordinates, the recovered camera pose for that view, and the
// resulting reprojection error.
struct ViewCalibration
{
    std::string image_name;
    linalg::Mat3 homography;
    CameraPose pose;
    double rms_error_px{0.0};
};

// Full output of calibrate_camera(): the shared intrinsics recovered across
// all views, the per-view pose/error breakdown, and the aggregate RMS
// reprojection error over every observed corner.
struct CalibrationReport
{
    Intrinsics intrinsics;
    std::vector<ViewCalibration> views;
    double overall_rms_error_px{0.0};
};

// Runs Zhang's planar calibration method over `dataset`: estimates a
// homography per view, solves for the shared intrinsics from the resulting
// image-of-the-absolute-conic constraints, then recovers each view's
// extrinsic pose and reprojection error. Fails if any view's homography is
// degenerate or the intrinsic solve is ill-conditioned.
[[nodiscard]] Result<CalibrationReport, Error> calibrate_camera(
    const CalibrationDataset& dataset);

// One observed/reprojected corner pair, for rendering a reprojection overlay
// over a single calibration image.
struct CornerReprojection
{
    int row{0};
    int col{0};
    linalg::Vec2 observed{};
    linalg::Vec2 reprojected{};
    double error_px{0.0};
};

// Closed-form pose estimate for a single view against already-known
// intrinsics: re-estimates that view's homography from its own
// observations, then decomposes it the same way `calibrate_camera` does.
// Unlike `ViewCalibration::pose` (which comes out of the joint nonlinear
// refinement across all included views), this never sees any other view, so
// it's the right tool for visualizing a view that has been excluded from
// calibration.
[[nodiscard]] Result<CameraPose, Error> estimate_view_pose(
    const BoardSpec& board, const ImageObservations& image,
    const Intrinsics& intrinsics);

// Reprojects every corner of `image` under `intrinsics`/`pose` and pairs
// each prediction with its observed pixel, for driving a reprojection-error
// overlay in a UI.
[[nodiscard]] std::vector<CornerReprojection> reproject_view(
    const BoardSpec& board, const ImageObservations& image,
    const Intrinsics& intrinsics, const CameraPose& pose);

}  // namespace week3
