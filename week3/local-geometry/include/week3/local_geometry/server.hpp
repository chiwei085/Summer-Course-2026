#pragma once

#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "week3/local_geometry/result.hpp"

// Forward-declared so this header stays Mongoose-free; only server.cpp
// includes <mongoose.h>.
struct mg_mgr;
struct mg_connection;

namespace week3::local_geometry
{

// An inbound HTTP request, reduced to the handful of fields our handlers
// ever look at.
struct Request
{
    std::string method;
    std::string path;
    std::string query;
    std::string body;

    [[nodiscard]] Option<std::string> query_param(std::string_view key) const;
};

// An HTTP response built through a small set of named constructors rather
// than public field mutation, mirroring the way `http::Response` builders
// read in Rust web frameworks.
struct Response
{
    int status{200};
    std::string content_type{"application/octet-stream"};
    std::vector<std::uint8_t> body;

    static Response json(std::string body_json);
    static Response png(std::vector<std::uint8_t> bytes);
    static Response text(std::string body_text);
    static Response not_found();
    static Response bad_request(std::string message);
};

using Handler = std::function<Response(const Request&)>;

struct ServerError
{
    std::string message;
};

// A tiny wrapper around Mongoose that only exposes what this project needs:
// registering GET routes, mounting a static directory, and running the
// event loop. Construction goes through `Builder` so a `HttpServer` is
// always fully configured before it exists.
class HttpServer
{
public:
    class Builder
    {
    public:
        Builder& listen_address(std::string addr);
        Builder& get(std::string path, Handler handler);
        Builder& static_dir(std::string url_prefix, std::filesystem::path root);

        [[nodiscard]] Result<HttpServer, ServerError> build();

    private:
        std::string listen_address_{"http://0.0.0.0:8080"};
        std::vector<std::pair<std::string, Handler>> routes_;
        std::vector<std::pair<std::string, std::filesystem::path>>
            static_mounts_;
    };

    static Builder builder() { return Builder{}; }

    HttpServer(HttpServer&&) noexcept;
    HttpServer& operator=(HttpServer&&) noexcept;
    HttpServer(const HttpServer&) = delete;
    HttpServer& operator=(const HttpServer&) = delete;
    ~HttpServer();

    // Blocks, polling the Mongoose event loop until `stop()` is called
    // (typically from a signal handler installed by the caller).
    void run();
    void stop();

    [[nodiscard]] const std::string& listen_address() const {
        return listen_address_;
    }

private:
    struct Impl;

    static void handle_event(mg_connection* connection, int event,
                             void* event_data);

    HttpServer(std::string listen_address,
               std::vector<std::pair<std::string, Handler>> routes,
               std::vector<std::pair<std::string, std::filesystem::path>>
                   static_mounts);

    std::string listen_address_;
    std::unique_ptr<Impl> impl_;
};

}  // namespace week3::local_geometry
