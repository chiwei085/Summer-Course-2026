#include <week3/calibration/linalg.hpp>

#include <cmath>

namespace week3::linalg
{

Result<std::vector<double>, Error> smallest_eigenvector_symmetric(
    Matrix matrix) {
    if (matrix.rows != matrix.cols || matrix.rows == 0) {
        return Result<std::vector<double>, Error>::err(
            {.message =
                 "Jacobi eigen solve expects a non-empty square matrix"});
    }

    const std::size_t n = matrix.rows;
    auto vectors = Matrix::zero(n, n);
    for (std::size_t i = 0; i < n; ++i) {
        vectors(i, i) = 1.0;
    }

    constexpr int kMaxSweeps = 100;
    constexpr double kTolerance = 1e-12;
    for (int sweep = 0; sweep < kMaxSweeps; ++sweep) {
        std::size_t p = 0;
        std::size_t q = 1;
        double largest = 0.0;
        for (std::size_t row = 0; row < n; ++row) {
            for (std::size_t col = row + 1; col < n; ++col) {
                const double value = std::abs(matrix(row, col));
                if (value > largest) {
                    largest = value;
                    p = row;
                    q = col;
                }
            }
        }
        if (largest < kTolerance) {
            break;
        }

        const double app = matrix(p, p);
        const double aqq = matrix(q, q);
        const double apq = matrix(p, q);
        const double tau = (aqq - app) / (2.0 * apq);
        const double sign = tau >= 0.0 ? 1.0 : -1.0;
        const double t = sign / (std::abs(tau) + std::sqrt(1.0 + tau * tau));
        const double cosine = 1.0 / std::sqrt(1.0 + t * t);
        const double sine = t * cosine;

        for (std::size_t k = 0; k < n; ++k) {
            if (k != p && k != q) {
                const double akp = matrix(k, p);
                const double akq = matrix(k, q);
                matrix(k, p) = cosine * akp - sine * akq;
                matrix(p, k) = matrix(k, p);
                matrix(k, q) = sine * akp + cosine * akq;
                matrix(q, k) = matrix(k, q);
            }
        }

        matrix(p, p) = cosine * cosine * app - 2.0 * sine * cosine * apq +
                       sine * sine * aqq;
        matrix(q, q) = sine * sine * app + 2.0 * sine * cosine * apq +
                       cosine * cosine * aqq;
        matrix(p, q) = 0.0;
        matrix(q, p) = 0.0;

        for (std::size_t k = 0; k < n; ++k) {
            const double vkp = vectors(k, p);
            const double vkq = vectors(k, q);
            vectors(k, p) = cosine * vkp - sine * vkq;
            vectors(k, q) = sine * vkp + cosine * vkq;
        }
    }

    std::size_t smallest = 0;
    for (std::size_t i = 1; i < n; ++i) {
        if (matrix(i, i) < matrix(smallest, smallest)) {
            smallest = i;
        }
    }

    std::vector<double> out(n);
    for (std::size_t i = 0; i < n; ++i) {
        out[i] = vectors(i, smallest);
    }
    return Result<std::vector<double>, Error>::ok(std::move(out));
}

Result<std::vector<double>, Error> solve_spd(Matrix a, std::vector<double> b) {
    if (a.rows != a.cols || a.rows != b.size()) {
        return Result<std::vector<double>, Error>::err(
            {.message = "solve_spd expects a square matrix matching the "
                        "right-hand side size"});
    }

    const std::size_t n = a.rows;
    Matrix lower = Matrix::zero(n, n);
    for (std::size_t i = 0; i < n; ++i) {
        for (std::size_t j = 0; j <= i; ++j) {
            double sum = a(i, j);
            for (std::size_t k = 0; k < j; ++k) {
                sum -= lower(i, k) * lower(j, k);
            }
            if (i == j) {
                if (sum <= 0.0) {
                    return Result<std::vector<double>, Error>::err(
                        {.message = "solve_spd: matrix is not positive "
                                    "definite"});
                }
                lower(i, i) = std::sqrt(sum);
            }
            else {
                lower(i, j) = sum / lower(j, j);
            }
        }
    }

    // Forward substitution: solve lower * y = b.
    std::vector<double> y(n);
    for (std::size_t i = 0; i < n; ++i) {
        double sum = b[i];
        for (std::size_t k = 0; k < i; ++k) {
            sum -= lower(i, k) * y[k];
        }
        y[i] = sum / lower(i, i);
    }

    // Back substitution: solve lower^T * x = y.
    std::vector<double> x(n);
    for (std::size_t i = n; i-- > 0;) {
        double sum = y[i];
        for (std::size_t k = i + 1; k < n; ++k) {
            sum -= lower(k, i) * x[k];
        }
        x[i] = sum / lower(i, i);
    }
    return Result<std::vector<double>, Error>::ok(std::move(x));
}

}  // namespace week3::linalg
