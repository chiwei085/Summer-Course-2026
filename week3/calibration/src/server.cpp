#include "week3/calibration/server.hpp"

#include <mongoose.h>

#include <cstdio>
#include <utility>

namespace week3
{
namespace
{

std::string to_std_string(mg_str s) {
    return {s.buf, s.len};
}

}  // namespace

Option<std::string> Request::query_param(std::string_view key) const {
    char value[1024];
    const mg_str query_str = mg_str_n(query.c_str(), query.size());
    const std::string key_owned{key};
    const int n =
        mg_http_get_var(&query_str, key_owned.c_str(), value, sizeof(value));
    if (n <= 0) return std::nullopt;
    return std::string{value, static_cast<std::size_t>(n)};
}

Response Response::json(std::string body_json) {
    Response r;
    r.status = 200;
    r.content_type = "application/json";
    r.body.assign(body_json.begin(), body_json.end());
    return r;
}

Response Response::text(std::string body_text) {
    Response r;
    r.status = 200;
    r.content_type = "text/plain";
    r.body.assign(body_text.begin(), body_text.end());
    return r;
}

Response Response::not_found() {
    Response r;
    r.status = 404;
    r.content_type = "text/plain";
    const std::string msg = "not found";
    r.body.assign(msg.begin(), msg.end());
    return r;
}

Response Response::bad_request(std::string message) {
    Response r;
    r.status = 400;
    r.content_type = "text/plain";
    r.body.assign(message.begin(), message.end());
    return r;
}

HttpServer::Builder& HttpServer::Builder::listen_address(std::string addr) {
    listen_address_ = std::move(addr);
    return *this;
}

HttpServer::Builder& HttpServer::Builder::get(std::string path,
                                              Handler handler) {
    routes_.emplace_back("GET " + path, std::move(handler));
    return *this;
}

HttpServer::Builder& HttpServer::Builder::static_dir(
    std::string url_prefix, std::filesystem::path root) {
    static_mounts_.emplace_back(std::move(url_prefix), std::move(root));
    return *this;
}

Result<HttpServer, ServerError> HttpServer::Builder::build() {
    return Result<HttpServer, ServerError>::ok(
        HttpServer{std::move(listen_address_), std::move(routes_),
                   std::move(static_mounts_)});
}

struct HttpServer::Impl
{
    mg_mgr mgr{};
    std::vector<std::pair<std::string, Handler>> routes;
    std::vector<std::pair<std::string, std::filesystem::path>> static_mounts;
    bool running{false};
};

void HttpServer::handle_event(mg_connection* c, int ev, void* ev_data) {
    if (ev != MG_EV_HTTP_MSG) return;
    auto* hm = static_cast<mg_http_message*>(ev_data);
    auto* impl = static_cast<HttpServer::Impl*>(c->fn_data);

    const std::string method = to_std_string(hm->method);
    const std::string path = to_std_string(hm->uri);
    const std::string route_key = method + " " + path;

    for (const auto& [key, handler] : impl->routes) {
        if (key != route_key) continue;
        Request req{
            .method = method,
            .path = path,
            .query = to_std_string(hm->query),
            .body = to_std_string(hm->body),
        };
        const Response res = handler(req);
        // mg_http_reply()'s body is a printf format string, which truncates
        // at embedded NUL bytes -- write the status line and headers
        // ourselves, then push the body as a raw byte buffer via mg_send().
        mg_printf(c,
                  "HTTP/1.1 %d %s\r\n"
                  "Content-Type: %s\r\n"
                  "Content-Length: %d\r\n"
                  "Access-Control-Allow-Origin: *\r\n"
                  "\r\n",
                  res.status, res.status == 200 ? "OK" : "Error",
                  res.content_type.c_str(), static_cast<int>(res.body.size()));
        mg_send(c, res.body.data(), res.body.size());
        c->is_resp = 0;
        return;
    }

    for (const auto& [prefix, root] : impl->static_mounts) {
        if (path.rfind(prefix, 0) != 0) continue;
        mg_http_serve_opts opts{};
        const std::string root_str = root.string();
        opts.root_dir = root_str.c_str();
        std::string rewritten = path.substr(prefix.size());
        if (rewritten.empty() || rewritten.front() != '/') {
            rewritten = "/" + rewritten;
        }
        mg_http_message rewritten_hm = *hm;
        rewritten_hm.uri = mg_str_n(rewritten.c_str(), rewritten.size());
        mg_http_serve_dir(c, &rewritten_hm, &opts);
        return;
    }

    mg_http_reply(c, 404, "Access-Control-Allow-Origin: *\r\n", "not found");
}

HttpServer::HttpServer(
    std::string listen_address,
    std::vector<std::pair<std::string, Handler>> routes,
    std::vector<std::pair<std::string, std::filesystem::path>> static_mounts)
    : listen_address_{std::move(listen_address)},
      impl_{std::make_unique<Impl>()} {
    impl_->routes = std::move(routes);
    impl_->static_mounts = std::move(static_mounts);
    mg_mgr_init(&impl_->mgr);
}

HttpServer::HttpServer(HttpServer&&) noexcept = default;
HttpServer& HttpServer::operator=(HttpServer&&) noexcept = default;

HttpServer::~HttpServer() {
    if (impl_) mg_mgr_free(&impl_->mgr);
}

void HttpServer::run() {
    mg_connection* c = mg_http_listen(&impl_->mgr, listen_address_.c_str(),
                                      &HttpServer::handle_event, impl_.get());
    if (!c) {
        std::fprintf(stderr, "failed to listen on %s\n",
                     listen_address_.c_str());
        return;
    }
    impl_->running = true;
    while (impl_->running) {
        mg_mgr_poll(&impl_->mgr, 1000);
    }
}

void HttpServer::stop() {
    impl_->running = false;
}

}  // namespace week3
