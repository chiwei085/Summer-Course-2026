#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "week3/calibration/api.hpp"
#include "week3/calibration/server.hpp"

namespace
{

week3::HttpServer* g_server = nullptr;

void handle_sigint(int) {
    if (g_server) g_server->stop();
}

}  // namespace

int main(int argc, char** argv) {
    const std::filesystem::path exe_dir =
        std::filesystem::absolute(argv[0]).parent_path();
    const std::filesystem::path project_root = exe_dir.parent_path();

    std::filesystem::path dataset_root =
        argc > 1 ? std::filesystem::path{argv[1]} : project_root / "data";
    std::string listen_address = argc > 2 ? argv[2] : "http://0.0.0.0:8080";

    auto app_result = week3::App::load(dataset_root);
    if (app_result.is_err()) {
        std::fprintf(stderr, "failed to load calibration dataset %s: %s\n",
                     dataset_root.string().c_str(),
                     app_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    week3::App app = std::move(app_result.value());
    auto server_result =
        week3::register_routes(
            week3::HttpServer::builder().listen_address(listen_address), app,
            project_root / "web", dataset_root)
            .build();
    if (server_result.is_err()) {
        std::fprintf(stderr, "failed to start server: %s\n",
                     server_result.error().message.c_str());
        return EXIT_FAILURE;
    }

    week3::HttpServer server = std::move(server_result.value());
    g_server = &server;
    std::signal(SIGINT, handle_sigint);

    std::printf("week3 calibration notebook listening on %s\n",
                server.listen_address().c_str());
    std::printf("open %s in a browser\n", server.listen_address().c_str());
    server.run();
    return EXIT_SUCCESS;
}
