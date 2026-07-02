#include "week3/calibration/api.hpp"

#include <nlohmann/json.hpp>

#include <cmath>
#include <cstddef>
#include <limits>

namespace week3
{
namespace
{

using Json = nlohmann::json;

constexpr int kMinIncludedViews = 3;

// A view's per-corner RMS is flagged as suspicious once it clears both a
// fixed floor (so a uniformly excellent calibration never flags anything)
// and a multiple of the mean across included views (so the threshold scales
// with how good the rest of the fit actually is).
bool is_suspicious(double rms_px, double mean_rms_px) {
    return rms_px > 0.5 && rms_px > 1.5 * mean_rms_px;
}

Json vec2_json(linalg::Vec2 v) {
    return Json{{"x", v.x}, {"y", v.y}};
}

}  // namespace

Result<App, AppError> App::load(std::filesystem::path dataset_root) {
    auto dataset = load_calibration_dataset(dataset_root);
    if (dataset.is_err()) {
        return Result<App, AppError>::err({.message = dataset.error().message});
    }
    return Result<App, AppError>::ok(App{std::move(dataset.value())});
}

App::App(CalibrationDataset dataset)
    : dataset_{std::move(dataset)},
      included_(dataset_.images.size(), true),
      report_{recompute()} {}

Result<CalibrationReport, Error> App::recompute() const {
    CalibrationDataset subset;
    subset.board = dataset_.board;
    for (std::size_t i = 0; i < dataset_.images.size(); ++i) {
        if (included_[i]) subset.images.push_back(dataset_.images[i]);
    }
    if (static_cast<int>(subset.images.size()) < kMinIncludedViews) {
        return Result<CalibrationReport, Error>::err(
            {.message = "at least " + std::to_string(kMinIncludedViews) +
                        " included images are required for calibration"});
    }
    return calibrate_camera(subset);
}

std::string App::summary_json() const {
    Json out;
    out["board"] = {
        {"cols", dataset_.board.cols},
        {"rows", dataset_.board.rows},
        {"square_size", dataset_.board.square_size},
    };
    out["min_included_views"] = kMinIncludedViews;
    out["ok"] = report_.is_ok();
    out["error"] =
        report_.is_ok() ? Json(nullptr) : Json(report_.error().message);

    double mean_rms = 0.0;
    if (report_.is_ok() && !report_.value().views.empty()) {
        double sum = 0.0;
        for (const auto& view : report_.value().views) sum += view.rms_error_px;
        mean_rms = sum / static_cast<double>(report_.value().views.size());
    }

    if (report_.is_ok()) {
        const CalibrationReport& r = report_.value();
        out["intrinsics"] = {
            {"fx", r.intrinsics.fx},     {"fy", r.intrinsics.fy},
            {"cx", r.intrinsics.cx},     {"cy", r.intrinsics.cy},
            {"skew", r.intrinsics.skew},
        };
        out["overall_rms_px"] = r.overall_rms_error_px;
    }
    else {
        out["intrinsics"] = nullptr;
        out["overall_rms_px"] = nullptr;
    }

    Json views = Json::array();
    for (std::size_t i = 0; i < dataset_.images.size(); ++i) {
        const ImageObservations& image = dataset_.images[i];
        double rms = 0.0;
        bool has_rms = false;
        if (report_.is_ok()) {
            for (const auto& view : report_.value().views) {
                if (view.image_name == image.image_name) {
                    rms = view.rms_error_px;
                    has_rms = true;
                    break;
                }
            }
        }
        views.push_back({
            {"name", image.image_name},
            {"included", included_[i]},
            {"corner_count", image.corners.size()},
            {"rms_px", has_rms ? Json(rms) : Json(nullptr)},
            {"suspicious", has_rms && is_suspicious(rms, mean_rms)},
        });
    }
    out["views"] = std::move(views);
    return out.dump();
}

Response App::handle_summary(const Request&) const {
    return Response::json(summary_json());
}

Response App::handle_view(const Request& req) const {
    const Option<std::string> name = req.query_param("name");
    if (!name) return Response::bad_request("missing 'name' query parameter");

    std::size_t idx = std::numeric_limits<std::size_t>::max();
    for (std::size_t i = 0; i < dataset_.images.size(); ++i) {
        if (dataset_.images[i].image_name == *name) {
            idx = i;
            break;
        }
    }
    if (idx == std::numeric_limits<std::size_t>::max())
        return Response::not_found();

    if (report_.is_err()) {
        Json out;
        out["ok"] = false;
        out["name"] = *name;
        out["error"] = report_.error().message;
        return Response::json(out.dump());
    }

    const ImageObservations& image = dataset_.images[idx];
    const Intrinsics& intrinsics = report_.value().intrinsics;

    CameraPose pose{};
    bool pose_is_refined = false;
    if (included_[idx]) {
        for (const auto& view : report_.value().views) {
            if (view.image_name == *name) {
                pose = view.pose;
                pose_is_refined = true;
                break;
            }
        }
    }
    if (!pose_is_refined) {
        auto estimated = estimate_view_pose(dataset_.board, image, intrinsics);
        if (estimated.is_err()) {
            Json out;
            out["ok"] = false;
            out["name"] = *name;
            out["error"] = estimated.error().message;
            return Response::json(out.dump());
        }
        pose = estimated.value();
    }

    const std::vector<CornerReprojection> corners =
        reproject_view(dataset_.board, image, intrinsics, pose);
    double squared_sum = 0.0;
    for (const auto& corner : corners)
        squared_sum += corner.error_px * corner.error_px;
    const double rms =
        corners.empty()
            ? 0.0
            : std::sqrt(squared_sum / static_cast<double>(corners.size()));

    Json corners_json = Json::array();
    for (const auto& corner : corners) {
        corners_json.push_back({
            {"row", corner.row},
            {"col", corner.col},
            {"observed", vec2_json(corner.observed)},
            {"reprojected", vec2_json(corner.reprojected)},
            {"error_px", corner.error_px},
        });
    }

    Json out;
    out["ok"] = true;
    out["name"] = *name;
    out["included"] = included_[idx];
    out["pose_is_refined"] = pose_is_refined;
    out["image_url"] = "/data/images/" + *name;
    out["image_width"] = image.image_size.width;
    out["image_height"] = image.image_size.height;
    out["rms_px"] = rms;
    out["corners"] = std::move(corners_json);
    return Response::json(out.dump());
}

Response App::handle_toggle(const Request& req) {
    const Option<std::string> name = req.query_param("name");
    const Option<std::string> included_raw = req.query_param("included");
    if (!name || !included_raw) {
        return Response::bad_request(
            "missing 'name' or 'included' query parameter");
    }

    std::size_t idx = std::numeric_limits<std::size_t>::max();
    for (std::size_t i = 0; i < dataset_.images.size(); ++i) {
        if (dataset_.images[i].image_name == *name) {
            idx = i;
            break;
        }
    }
    if (idx == std::numeric_limits<std::size_t>::max())
        return Response::not_found();

    const bool want_included = *included_raw == "1" || *included_raw == "true";
    if (!want_included) {
        int remaining = 0;
        for (std::size_t i = 0; i < included_.size(); ++i) {
            if (i != idx && included_[i]) ++remaining;
        }
        if (remaining < kMinIncludedViews) {
            return Response::bad_request(
                "at least " + std::to_string(kMinIncludedViews) +
                " included images are required for calibration");
        }
    }

    included_[idx] = want_included;
    report_ = recompute();
    return Response::json(summary_json());
}

HttpServer::Builder register_routes(HttpServer::Builder builder, App& app,
                                    std::filesystem::path web_root,
                                    std::filesystem::path dataset_root) {
    return std::move(builder)
        .get("/api/summary",
             [&app](const Request& req) { return app.handle_summary(req); })
        .get("/api/view",
             [&app](const Request& req) { return app.handle_view(req); })
        .get("/api/toggle",
             [&app](const Request& req) { return app.handle_toggle(req); })
        .static_dir("/data", std::move(dataset_root))
        .static_dir("/", std::move(web_root));
}

}  // namespace week3
