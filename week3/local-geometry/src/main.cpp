#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "week3/local_geometry/api.hpp"
#include "week3/local_geometry/server.hpp"

namespace
{

week3::local_geometry::HttpServer* g_server = nullptr;

void handle_sigint(int) {
    if (g_server) g_server->stop();
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path exe_dir =
        std::filesystem::absolute(argv[0]).parent_path();
    const std::filesystem::path project_root = exe_dir.parent_path();

    const std::filesystem::path edges_image_path =
        project_root / "images" / "scissors.png";
    const std::filesystem::path corners_image_path =
        project_root / "images" / "building.jpg";
    const std::filesystem::path lines_image_path =
        project_root / "images" / "solidWhiteRight.jpg";
    std::string listen_address = argc > 1 ? argv[1] : "http://0.0.0.0:8080";

    auto app_result = week3::local_geometry::App::load(
        edges_image_path, corners_image_path, lines_image_path);
    if (app_result.is_err()) {
        std::fprintf(stderr, "failed to load sample images: %s\n",
                     app_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    auto server_result =
        week3::local_geometry::register_routes(
            week3::local_geometry::HttpServer::builder().listen_address(
                listen_address),
            app_result.value(), project_root / "web")
            .build();
    if (server_result.is_err()) {
        std::fprintf(stderr, "failed to start server: %s\n",
                     server_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    week3::local_geometry::HttpServer server = std::move(server_result.value());
    g_server = &server;
    std::signal(SIGINT, handle_sigint);

    std::printf("week3 local-geometry notebook listening on %s\n",
                server.listen_address().c_str());
    std::printf("open %s in a browser\n", server.listen_address().c_str());
    server.run();
    return EXIT_SUCCESS;
}
