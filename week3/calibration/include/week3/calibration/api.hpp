#pragma once

#include <filesystem>
#include <vector>

#include "week3/calibration/calibration.hpp"
#include "week3/calibration/dataset.hpp"
#include "week3/calibration/result.hpp"
#include "week3/calibration/server.hpp"

namespace week3
{

struct AppError
{
    std::string message;
};

// Owns the full calibration dataset (every image, whether or not it's
// currently included) plus which views are included, and knows how to
// answer every route the notebook frontend calls. Recalibration happens
// synchronously on load and on every include/exclude toggle -- the dataset
// is small enough (a handful of views, a few dozen corners each) that this
// stays well under interactive latency.
class App
{
public:
    static Result<App, AppError> load(std::filesystem::path dataset_root);

    [[nodiscard]] Response handle_summary(const Request&) const;
    [[nodiscard]] Response handle_view(const Request&) const;
    [[nodiscard]] Response handle_toggle(const Request&);

private:
    explicit App(CalibrationDataset dataset);

    [[nodiscard]] Result<CalibrationReport, Error> recompute() const;
    [[nodiscard]] std::string summary_json() const;

    CalibrationDataset dataset_;
    std::vector<bool> included_;
    Result<CalibrationReport, Error> report_;
};

// Wires every `App` handler into a server builder under `/api/...`, mounts
// `web_root` at `/`, and mounts `dataset_root` at `/data` so the frontend
// can load the raw calibration images directly.
[[nodiscard]] HttpServer::Builder register_routes(
    HttpServer::Builder builder, App& app, std::filesystem::path web_root,
    std::filesystem::path dataset_root);

}  // namespace week3
