# Problem 1: Graceful Degradation Load Balancer

Design and implement a load balancer in Python that gracefully degrades under increasing load. When backend servers become unhealthy or response times increase, the system should shed load intelligently rather than failing catastrophically.

## Requirements

- Route incoming requests across multiple backend servers
- Health checking with configurable intervals
- When backends degrade: shed lowest-priority traffic first
- When backends recover: gradually restore full capacity (don't thundering-herd)
- Priority levels for different request types (critical, normal, background)
- Provide a simple simulation that demonstrates the graceful degradation behaviour

## Deliverable

A working Python implementation with a simulation showing the system handling:
1. Normal operation with even load distribution
2. One backend becoming slow — system adapts
3. Multiple backends failing — graceful shedding
4. Recovery — gradual ramp-up

Write all code to a `load_balancer/` directory.
