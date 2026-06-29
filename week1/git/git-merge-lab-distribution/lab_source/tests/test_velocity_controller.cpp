#include "velocity_controller.hpp"

#include <cmath>
#include <iostream>

namespace {

bool close_to(double actual, double expected)
{
    return std::abs(actual - expected) < 1e-9;
}

}  // namespace

int main()
{
    const VelocityController controller;
    const VelocityReading reading{1.0};
    const VelocityTarget target{1.5};

    const double command = controller.compute_command(reading, target);
    if (!close_to(command, 0.5)) {
        std::cerr << "expected 0.5, got " << command << '\n';
        return 1;
    }

    return 0;
}

