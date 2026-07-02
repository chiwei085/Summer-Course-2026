#pragma once

#include <string>
#include <utility>
#include <variant>

namespace week3
{

template <class T, class E>
class Result
{
public:
    static Result ok(T value) { return Result{std::move(value)}; }
    static Result err(E error) { return Result{std::move(error)}; }

    [[nodiscard]] bool is_ok() const {
        return std::holds_alternative<T>(data_);
    }
    [[nodiscard]] bool is_err() const { return !is_ok(); }

    T& value() { return std::get<T>(data_); }
    const T& value() const { return std::get<T>(data_); }

    E& error() { return std::get<E>(data_); }
    const E& error() const { return std::get<E>(data_); }

private:
    explicit Result(T value) : data_{std::move(value)} {}
    explicit Result(E error) : data_{std::move(error)} {}

    std::variant<T, E> data_;
};

struct Error
{
    std::string message;
};

}  // namespace week3
