#include <week3/calibration/calibration.hpp>
#include <week3/calibration/dataset.hpp>

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <string_view>

namespace
{

constexpr double kPinholeRmsPassThresholdPx = 3.0;

void write_stdout(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stdout);
}

void write_stderr(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stderr);
}

void print_matrix(const week3::linalg::Mat3& matrix) {
    for (int row = 0; row < 3; ++row) {
        write_stdout(std::format("    [{: .8f} {: .8f} {: .8f}]\n",
                                 matrix(row, 0), matrix(row, 1),
                                 matrix(row, 2)));
    }
}

void print_report(const week3::CalibrationDataset& dataset,
                  const week3::CalibrationReport& report) {
    write_stdout(std::format(
        "camera calibration from {} images, {}x{} inner corners\n\n",
        dataset.images.size(), dataset.board.cols, dataset.board.rows));

    write_stdout("intrinsics K:\n");
    print_matrix(report.intrinsics.matrix());
    write_stdout(
        std::format("\nparameters:\n"
                    "  fx    = {:.6f}\n"
                    "  fy    = {:.6f}\n"
                    "  cx    = {:.6f}\n"
                    "  cy    = {:.6f}\n"
                    "  skew  = {:.6f}\n"
                    "  rms   = {:.6f} px\n\n",
                    report.intrinsics.fx, report.intrinsics.fy,
                    report.intrinsics.cx, report.intrinsics.cy,
                    report.intrinsics.skew, report.overall_rms_error_px));

    write_stdout("per-view extrinsics and reprojection error:\n");
    for (const auto& view : report.views) {
        write_stdout(std::format(
            "  {}: rms = {:.6f} px, t = [{:.6f}, {:.6f}, {:.6f}]\n",
            view.image_name, view.rms_error_px, view.pose.translation.x,
            view.pose.translation.y, view.pose.translation.z));
    }
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path dataset_root =
        argc > 1 ? std::filesystem::path{argv[1]}
                 : std::filesystem::path{"data"};

    auto dataset = week3::load_calibration_dataset(dataset_root);
    if (dataset.is_err()) {
        write_stderr(
            std::format("dataset error: {}\n", dataset.error().message));
        return EXIT_FAILURE;
    }

    auto report = week3::calibrate_camera(dataset.value());
    if (report.is_err()) {
        write_stderr(
            std::format("calibration error: {}\n", report.error().message));
        return EXIT_FAILURE;
    }

    print_report(dataset.value(), report.value());
    return report.value().overall_rms_error_px < kPinholeRmsPassThresholdPx
               ? EXIT_SUCCESS
               : EXIT_FAILURE;
}
