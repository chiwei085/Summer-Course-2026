#include "velocity_controller.hpp"

double VelocityController::compute_command(
    const VelocityReading& reading,
    const VelocityTarget& target) const
{
    return target.desired_meters_per_second
         - reading.meters_per_second;
}

