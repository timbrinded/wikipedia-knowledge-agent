# Problem 5: Fleet Delivery Route Optimisation

Design and implement a delivery routing optimiser in Python for a fleet of vehicles. Given a set of delivery locations and a fleet of vehicles with capacity constraints, find efficient routes that minimise total distance while respecting constraints.

## Requirements

- Multiple vehicles, each with a max capacity (weight/volume)
- Delivery locations with coordinates, demand (weight), and time windows
- Vehicles start and end at a depot
- Optimise for total distance travelled across all vehicles
- Handle the case where not all deliveries can be made (prioritise by urgency)
- Visualise the resulting routes (text-based is fine)

## Deliverable

A working Python implementation with:
1. The routing algorithm
2. A problem generator that creates realistic delivery scenarios
3. A baseline (nearest-neighbour greedy) for comparison
4. Results showing your approach vs the baseline on generated problems

Write all code to a `routing/` directory.
