#pragma once

struct VelocityReading {
    double meters_per_second;
};

struct VelocityTarget {
    double desired_meters_per_second;
};

class VelocityController {
public:
    double compute_command(
        const VelocityReading& reading,
        const VelocityTarget& target) const;
};

