#!/usr/bin/env python3
"""
Load Balancer Benchmark — 7 scenarios testing design quality.

Imports a LoadBalancer implementation from a workspace and runs deterministic,
tick-based scenarios. Produces a JSON report with per-scenario scores (0.0–1.0)
and a weighted aggregate score (0–100).

Usage:
    python3 01_load_balancer.py --workspace /path/to/workspace --output results.json [--seed 42]
"""

from __future__ import annotations

import argparse
import importlib
import json
import random
import statistics
import sys
import traceback
from dataclasses import dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# Simulated Backend (implements BackendHandle protocol, invisible to agent)
# ---------------------------------------------------------------------------

class SimulatedBackend:
    """
    Benchmark-controlled backend that implements the BackendHandle protocol.

    The agent sees only name, send_request(), and health_probe().
    The benchmark controls fault injection via kill/revive/degrade.
    """

    def __init__(self, name: str, base_latency_ms: float = 50.0, rng: random.Random | None = None):
        self._name = name
        self._base_latency_ms = base_latency_ms
        self._rng = rng or random.Random()
        self._alive = True
        self._latency_multiplier = 1.0
        self._error_rate = 0.0

    @property
    def name(self) -> str:
        return self._name

    def send_request(self) -> tuple[bool, float]:
        if not self._alive:
            return (False, 0.0)
        latency = self._base_latency_ms * self._latency_multiplier
        # Add jitter (±10%)
        latency *= 1.0 + self._rng.uniform(-0.1, 0.1)
        if self._rng.random() < self._error_rate:
            return (False, latency)
        return (True, latency)

    def health_probe(self) -> tuple[bool, float]:
        if not self._alive:
            return (False, 0.0)
        latency = self._base_latency_ms * self._latency_multiplier * 0.1
        latency *= 1.0 + self._rng.uniform(-0.1, 0.1)
        return (True, latency)

    # --- Fault injection (benchmark only, not on protocol) ---

    def kill(self) -> None:
        self._alive = False

    def revive(self) -> None:
        self._alive = True
        self._latency_multiplier = 1.0
        self._error_rate = 0.0

    def degrade(self, latency_multiplier: float, error_rate: float) -> None:
        self._latency_multiplier = latency_multiplier
        self._error_rate = error_rate

    def reset(self) -> None:
        self._alive = True
        self._latency_multiplier = 1.0
        self._error_rate = 0.0


# ---------------------------------------------------------------------------
# Scenario infrastructure
# ---------------------------------------------------------------------------

@dataclass
class ScenarioResult:
    name: str
    score: float  # 0.0 – 1.0
    weight: float
    details: dict = field(default_factory=dict)
    error: str | None = None


def make_requests(tick: int, count: int, rng: random.Random, priority_weights: tuple[float, float, float] = (1, 1, 1)) -> list:
    """Generate requests for a tick with given priority distribution."""
    # Import here to use from the contract
    from load_balancer.types import Priority, Request

    priorities = [Priority.BACKGROUND, Priority.NORMAL, Priority.CRITICAL]
    weights = list(priority_weights)
    requests = []
    for i in range(count):
        p = rng.choices(priorities, weights=weights, k=1)[0]
        requests.append(Request(id=tick * 10000 + i, priority=p, tick=tick))
    return requests


def run_tick(lb, tick: int, requests: list) -> list:
    """Run one simulation tick: call tick(), then handle each request."""
    lb.tick()
    responses = []
    for req in requests:
        resp = lb.handle_request(req)
        responses.append(resp)
    return responses


# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------

def coefficient_of_variation(values: list) -> float:
    """CV = stddev / mean. Lower = more even distribution."""
    if not values or all(v == 0 for v in values):
        return 0.0
    mean = statistics.mean(values)
    if mean == 0:
        return 0.0
    return statistics.stdev(values) / mean if len(values) > 1 else 0.0


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


# ---------------------------------------------------------------------------
# Scenario 1: Steady State
# ---------------------------------------------------------------------------

def scenario_steady_state(lb_class, seed: int) -> ScenarioResult:
    """3 healthy backends, 30 req/tick, 50 ticks. Measures baseline routing quality."""
    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(3)]
    lb = lb_class(backends)

    backend_counts: dict[str, int] = {b.name: 0 for b in backends}
    total_admitted = 0
    total_success = 0
    total_requests = 0

    for tick in range(50):
        reqs = make_requests(tick, 30, rng)
        total_requests += len(reqs)
        resps = run_tick(lb, tick, reqs)
        for r in resps:
            if r.admitted:
                total_admitted += 1
                if r.backend_name in backend_counts:
                    backend_counts[r.backend_name] += 1
                if r.success:
                    total_success += 1

    # Score: evenness of distribution + high admission rate
    counts = list(backend_counts.values())
    cv = coefficient_of_variation(counts)
    admission_rate = total_admitted / total_requests if total_requests else 0
    success_rate = total_success / total_admitted if total_admitted else 0

    # CV of 0 = perfect, CV > 0.5 = bad
    evenness_score = clamp(1.0 - cv * 2)
    admission_score = admission_rate
    success_score = success_rate

    score = 0.4 * evenness_score + 0.3 * admission_score + 0.3 * success_score

    return ScenarioResult(
        name="steady_state",
        score=clamp(score),
        weight=1.0,
        details={
            "backend_counts": backend_counts,
            "cv": round(cv, 4),
            "admission_rate": round(admission_rate, 4),
            "success_rate": round(success_rate, 4),
            "evenness_score": round(evenness_score, 4),
        },
    )


# ---------------------------------------------------------------------------
# Scenario 2: Degradation Detection
# ---------------------------------------------------------------------------

def scenario_degradation_detection(lb_class, seed: int) -> ScenarioResult:
    """
    3 backends. Tick 10: A degrades (6x latency, 30% errors). Tick 60: A recovers.
    Measures detection speed — how fast traffic shifts away from A.
    """
    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(3)]
    lb = lb_class(backends)

    detection_tick = None
    error_count_during_detection = 0
    total_during_detection = 0

    for tick in range(80):
        # Fault injection
        if tick == 10:
            backends[0].degrade(latency_multiplier=6.0, error_rate=0.3)
        if tick == 60:
            backends[0].revive()

        reqs = make_requests(tick, 30, rng)
        resps = run_tick(lb, tick, reqs)

        # Track B0's traffic share after degradation
        if 10 <= tick <= 60:
            b0_count = sum(1 for r in resps if r.backend_name == backends[0].name and r.admitted)
            total_count = sum(1 for r in resps if r.admitted)
            total_during_detection += total_count

            # Count errors routed to B0
            error_count_during_detection += sum(
                1 for r in resps if r.backend_name == backends[0].name and r.admitted and not r.success
            )

            # Detection = B0 gets < 20% of traffic
            if detection_tick is None and total_count > 0:
                share = b0_count / total_count
                if share < 0.20:
                    detection_tick = tick

    # Score: faster detection = better
    if detection_tick is None:
        detection_speed_score = 0.0
        ticks_to_detect = 999
    else:
        ticks_to_detect = detection_tick - 10
        # 1 tick = perfect (1.0), 20+ ticks = terrible (0.0)
        detection_speed_score = clamp(1.0 - ticks_to_detect / 20)

    # Penalty for errors during detection window
    error_rate = error_count_during_detection / total_during_detection if total_during_detection else 0
    error_penalty = clamp(1.0 - error_rate * 5)  # Each 20% error rate = full penalty

    score = 0.7 * detection_speed_score + 0.3 * error_penalty

    return ScenarioResult(
        name="degradation_detection",
        score=clamp(score),
        weight=2.0,
        details={
            "ticks_to_detect": ticks_to_detect,
            "detection_tick": detection_tick,
            "error_rate_during_detection": round(error_rate, 4),
            "detection_speed_score": round(detection_speed_score, 4),
        },
    )


# ---------------------------------------------------------------------------
# Scenario 3: Priority Protection
# ---------------------------------------------------------------------------

def scenario_priority_protection(lb_class, seed: int) -> ScenarioResult:
    """
    3 backends, 40 req/tick (overload), equal priority mix.
    Tick 10: A killed. Tick 30: B degraded. Tick 60: B killed. Tick 80: both revive.
    Measures: critical success rate + correct priority ordering of shed rates.
    """
    from load_balancer.types import Priority

    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(3)]
    lb = lb_class(backends)

    # Track per-priority outcomes during stress (ticks 10-80)
    priority_admitted: dict[int, int] = {p: 0 for p in Priority}
    priority_total: dict[int, int] = {p: 0 for p in Priority}
    priority_success: dict[int, int] = {p: 0 for p in Priority}
    zero_throughput_ticks = 0

    for tick in range(100):
        if tick == 10:
            backends[0].kill()
        if tick == 30:
            backends[1].degrade(latency_multiplier=4.0, error_rate=0.25)
        if tick == 60:
            backends[1].kill()
        if tick == 80:
            backends[0].revive()
            backends[1].revive()

        reqs = make_requests(tick, 40, rng)
        resps = run_tick(lb, tick, reqs)

        if 10 <= tick < 80:
            tick_admitted = 0
            for req, resp in zip(reqs, resps):
                priority_total[req.priority] += 1
                if resp.admitted:
                    priority_admitted[req.priority] += 1
                    tick_admitted += 1
                    if resp.success:
                        priority_success[req.priority] += 1
            if tick_admitted == 0:
                zero_throughput_ticks += 1

    # Per-priority success rates (success / total, counting failed routing as failure)
    success_rates = {}
    for p in Priority:
        if priority_total[p] > 0:
            success_rates[p.name] = priority_success[p] / priority_total[p]
        else:
            success_rates[p.name] = 0.0

    crit_rate = success_rates.get("CRITICAL", 0.0)
    bg_rate = success_rates.get("BACKGROUND", 0.0)

    # Priority differentiation: critical should have higher success than background
    # If no differentiation (naive), this scores 0
    differentiation = crit_rate - bg_rate
    diff_score = clamp(differentiation / 0.3)  # 30%+ gap = full score

    # Shed rate ordering: background should be shed most, critical least
    shed_rates = {}
    for p in Priority:
        if priority_total[p] > 0:
            shed_rates[p.name] = 1.0 - (priority_admitted[p] / priority_total[p])

    # Check correct ordering: shed(BACKGROUND) >= shed(NORMAL) >= shed(CRITICAL)
    ordering_correct = True
    has_any_shedding = any(v > 0.01 for v in shed_rates.values())
    if len(shed_rates) == 3 and has_any_shedding:
        if shed_rates["BACKGROUND"] < shed_rates["NORMAL"] - 0.05:
            ordering_correct = False
        if shed_rates["NORMAL"] < shed_rates["CRITICAL"] - 0.05:
            ordering_correct = False
    elif not has_any_shedding:
        # No shedding at all during a stress period = not protecting priorities
        ordering_correct = False

    ordering_score = 1.0 if ordering_correct else 0.0

    # Penalize zero-throughput ticks (total blackout)
    zero_penalty = clamp(1.0 - zero_throughput_ticks / 10)

    score = 0.35 * crit_rate + 0.30 * diff_score + 0.20 * ordering_score + 0.15 * zero_penalty

    return ScenarioResult(
        name="priority_protection",
        score=clamp(score),
        weight=3.0,
        details={
            "critical_success_rate": round(crit_rate, 4),
            "background_success_rate": round(bg_rate, 4),
            "differentiation": round(differentiation, 4),
            "shed_rates": {k: round(v, 4) for k, v in shed_rates.items()},
            "ordering_correct": ordering_correct,
            "has_any_shedding": has_any_shedding,
            "zero_throughput_ticks": zero_throughput_ticks,
        },
    )


# ---------------------------------------------------------------------------
# Scenario 4: Recovery Smoothness
# ---------------------------------------------------------------------------

def scenario_recovery_smoothness(lb_class, seed: int) -> ScenarioResult:
    """
    3 backends. Tick 5: A+B killed. Tick 30: A revives. Tick 50: B revives.
    Measures: monotonic ramp-up + no overshoot + shed decreasing during recovery.
    """
    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(3)]
    lb = lb_class(backends)

    # Track success rate (not just admission) per tick during recovery
    recovery_success_rates: list[float] = []  # ticks 30-70
    fault_success_rates: list[float] = []  # ticks 5-30 (during outage)
    shed_counts_recovery: list[int] = []

    for tick in range(80):
        if tick == 5:
            backends[0].kill()
            backends[1].kill()
        if tick == 30:
            backends[0].revive()
        if tick == 50:
            backends[1].revive()

        reqs = make_requests(tick, 30, rng)
        resps = run_tick(lb, tick, reqs)

        if 5 <= tick < 30:
            # During outage: measure success rate (naive will be low here)
            success = sum(1 for r in resps if r.success)
            rate = success / len(resps) if resps else 0
            fault_success_rates.append(rate)

        if 30 <= tick < 70:
            success = sum(1 for r in resps if r.success)
            shed = sum(1 for r in resps if r.shed or not r.admitted)
            rate = success / len(resps) if resps else 0
            recovery_success_rates.append(rate)
            shed_counts_recovery.append(shed)

    # Monotonicity of success rate during recovery (smoothed over 3-tick windows)
    if len(recovery_success_rates) >= 3:
        smoothed = []
        for i in range(len(recovery_success_rates) - 2):
            window = recovery_success_rates[i : i + 3]
            smoothed.append(statistics.mean(window))

        decreases = sum(1 for i in range(1, len(smoothed)) if smoothed[i] < smoothed[i - 1] - 0.05)
        monotonicity_score = clamp(1.0 - decreases / max(len(smoothed) - 1, 1))
    else:
        monotonicity_score = 0.5

    # Success rate during fault window: smart implementations shed to maintain
    # high success on what they do admit. Naive admits everything, gets ~33% success.
    avg_fault_success = statistics.mean(fault_success_rates) if fault_success_rates else 0
    fault_handling_score = clamp(avg_fault_success)

    # Shed should decrease during recovery
    if len(shed_counts_recovery) >= 4:
        first_half = statistics.mean(shed_counts_recovery[: len(shed_counts_recovery) // 2])
        second_half = statistics.mean(shed_counts_recovery[len(shed_counts_recovery) // 2 :])
        shed_decreasing = second_half <= first_half + 1
        shed_score = 1.0 if shed_decreasing else 0.3
    else:
        shed_score = 0.5

    # Final success rate should be high (backends all healthy)
    final_rate = statistics.mean(recovery_success_rates[-5:]) if len(recovery_success_rates) >= 5 else 0
    final_score = clamp(final_rate)

    score = 0.3 * monotonicity_score + 0.25 * fault_handling_score + 0.2 * shed_score + 0.25 * final_score

    return ScenarioResult(
        name="recovery_smoothness",
        score=clamp(score),
        weight=2.0,
        details={
            "monotonicity_score": round(monotonicity_score, 4),
            "fault_handling_score": round(fault_handling_score, 4),
            "avg_fault_success_rate": round(avg_fault_success, 4),
            "shed_decreasing": shed_score == 1.0,
            "final_success_rate": round(final_rate, 4),
        },
    )


# ---------------------------------------------------------------------------
# Scenario 5: Cascading Failure Prevention
# ---------------------------------------------------------------------------

def scenario_cascading_failure(lb_class, seed: int) -> ScenarioResult:
    """
    4 backends, 50 req/tick. Tick 10: A killed. Tick 25: B degrades.
    Tick 40: B worsens. Tick 60: A+B revive.
    Measures: cascade prevention + healthy backend protection.
    """
    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(4)]
    lb = lb_class(backends)

    # Track healthy backend (C, D) overload and overall throughput
    healthy_success: list[int] = []  # per-tick success on C+D during stress
    total_success_per_tick: list[int] = []
    b_traffic_after_degrade: list[int] = []

    for tick in range(80):
        if tick == 10:
            backends[0].kill()
        if tick == 25:
            backends[1].degrade(latency_multiplier=3.0, error_rate=0.2)
        if tick == 40:
            backends[1].degrade(latency_multiplier=6.0, error_rate=0.5)
        if tick == 60:
            backends[0].revive()
            backends[1].revive()

        reqs = make_requests(tick, 50, rng)
        resps = run_tick(lb, tick, reqs)

        if 10 <= tick < 60:
            cd_success = sum(1 for r in resps if r.backend_name in ("B2", "B3") and r.success)
            healthy_success.append(cd_success)
            total_success_per_tick.append(sum(1 for r in resps if r.success))

        if 25 <= tick < 60:
            b_count = sum(1 for r in resps if r.backend_name == "B1" and r.admitted)
            b_traffic_after_degrade.append(b_count)

    # Healthy backend protection: C+D should maintain reasonable throughput
    avg_healthy = statistics.mean(healthy_success) if healthy_success else 0
    # With 50 req/tick and 2 healthy backends at 50ms, they can handle ~25 each
    protection_score = clamp(avg_healthy / 20)  # 20+ success/tick on healthy = good

    # B traffic should reduce after degradation
    avg_b_traffic = statistics.mean(b_traffic_after_degrade) if b_traffic_after_degrade else 0
    # 50 req / 4 backends = ~12.5 baseline. Should be much lower after degrade.
    cascade_prevention = clamp(1.0 - avg_b_traffic / 12.5)

    # Overall throughput preservation
    avg_throughput = statistics.mean(total_success_per_tick) if total_success_per_tick else 0
    throughput_score = clamp(avg_throughput / 30)  # 30+ success/tick = good

    score = 0.4 * protection_score + 0.3 * cascade_prevention + 0.3 * throughput_score

    return ScenarioResult(
        name="cascading_failure",
        score=clamp(score),
        weight=2.0,
        details={
            "avg_healthy_success_per_tick": round(avg_healthy, 2),
            "avg_b_traffic_after_degrade": round(avg_b_traffic, 2),
            "avg_total_throughput": round(avg_throughput, 2),
            "protection_score": round(protection_score, 4),
            "cascade_prevention": round(cascade_prevention, 4),
        },
    )


# ---------------------------------------------------------------------------
# Scenario 6: Intermittent Flapping
# ---------------------------------------------------------------------------

def scenario_flapping(lb_class, seed: int) -> ScenarioResult:
    """
    3 backends. Ticks 10-60: A alternates degraded/healthy every 3 ticks.
    Tick 61: A stabilizes. Measures: dampening + critical always admitted + convergence.
    """
    from load_balancer.types import Priority

    rng = random.Random(seed)
    backends = [SimulatedBackend(f"B{i}", base_latency_ms=50.0, rng=random.Random(seed + i)) for i in range(3)]
    lb = lb_class(backends)

    a_shares: list[float] = []  # A's traffic share per tick during flapping
    critical_success = 0
    critical_total = 0
    flap_errors = 0  # errors during flapping from routing to degraded A
    flap_total = 0
    post_flap_shares: list[float] = []  # A's share after flapping ends

    for tick in range(80):
        # Flapping: A alternates every 3 ticks between degraded and healthy
        if 10 <= tick <= 60:
            cycle = (tick - 10) // 3
            if cycle % 2 == 0:
                backends[0].degrade(latency_multiplier=5.0, error_rate=0.3)
            else:
                backends[0].revive()
        if tick == 61:
            backends[0].revive()

        reqs = make_requests(tick, 30, rng)
        resps = run_tick(lb, tick, reqs)

        admitted = [r for r in resps if r.admitted]
        a_count = sum(1 for r in admitted if r.backend_name == "B0")
        share = a_count / len(admitted) if admitted else 0

        if 10 <= tick <= 60:
            a_shares.append(share)
            flap_total += len(resps)
            flap_errors += sum(1 for r in resps if r.admitted and not r.success)
            for req, resp in zip(reqs, resps):
                if req.priority == Priority.CRITICAL:
                    critical_total += 1
                    if resp.success:
                        critical_success += 1

        if 61 <= tick < 80:
            post_flap_shares.append(share)

    # Dampening: low variance of A's share = good (not oscillating wildly)
    share_std = 0.0
    if len(a_shares) >= 2:
        share_std = statistics.stdev(a_shares)
        # Perfect dampening = std ~0. Wild oscillation = std ~0.3+
        dampening_score = clamp(1.0 - share_std / 0.3)
    else:
        dampening_score = 0.5

    # Critical success rate (not just admission — penalizes routing to degraded A)
    crit_rate = critical_success / critical_total if critical_total else 1.0
    crit_score = clamp(crit_rate)

    # Error rate during flapping — penalizes naive implementations that keep
    # routing to A during its degraded phases
    flap_error_rate = flap_errors / flap_total if flap_total else 0
    error_score = clamp(1.0 - flap_error_rate * 5)  # 20% error rate = 0

    # Post-flap convergence: A should return to ~33% share
    if post_flap_shares:
        final_avg = statistics.mean(post_flap_shares[-5:]) if len(post_flap_shares) >= 5 else statistics.mean(post_flap_shares)
        convergence_score = clamp(1.0 - abs(final_avg - 0.333) * 3)
    else:
        convergence_score = 0.5

    score = 0.30 * dampening_score + 0.25 * crit_score + 0.25 * error_score + 0.20 * convergence_score

    return ScenarioResult(
        name="flapping",
        score=clamp(score),
        weight=1.5,
        details={
            "share_stddev": round(share_std, 4),
            "dampening_score": round(dampening_score, 4),
            "critical_success_rate": round(crit_rate, 4),
            "flap_error_rate": round(flap_error_rate, 4),
            "error_score": round(error_score, 4),
            "post_flap_avg_share": round(statistics.mean(post_flap_shares) if post_flap_shares else 0, 4),
            "convergence_score": round(convergence_score, 4),
        },
    )


# ---------------------------------------------------------------------------
# Scenario 7: Asymmetric Backends
# ---------------------------------------------------------------------------

def scenario_asymmetric(lb_class, seed: int) -> ScenarioResult:
    """
    3 backends with latencies 20ms/50ms/150ms. 60 ticks, no faults.
    Measures: traffic ordering matches inverse latency + low avg latency + zero shedding.
    """
    rng = random.Random(seed)
    backends = [
        SimulatedBackend("Fast", base_latency_ms=20.0, rng=random.Random(seed)),
        SimulatedBackend("Medium", base_latency_ms=50.0, rng=random.Random(seed + 1)),
        SimulatedBackend("Slow", base_latency_ms=150.0, rng=random.Random(seed + 2)),
    ]
    lb = lb_class(backends)

    backend_counts: dict[str, int] = {"Fast": 0, "Medium": 0, "Slow": 0}
    total_latency = 0.0
    total_admitted = 0
    total_shed = 0
    total_requests = 0

    for tick in range(60):
        reqs = make_requests(tick, 30, rng)
        total_requests += len(reqs)
        resps = run_tick(lb, tick, reqs)

        for r in resps:
            if r.admitted:
                total_admitted += 1
                total_latency += r.latency_ms
                if r.backend_name in backend_counts:
                    backend_counts[r.backend_name] += 1
            if r.shed or not r.admitted:
                total_shed += 1

    # Traffic ordering: Fast > Medium > Slow
    ordering_correct = backend_counts["Fast"] >= backend_counts["Medium"] >= backend_counts["Slow"]

    # Ratio quality: how much more does Fast get vs Slow?
    if backend_counts["Slow"] > 0:
        ratio = backend_counts["Fast"] / backend_counts["Slow"]
        # Ideal: Fast/Slow ≈ 150/20 = 7.5x. Even 2x is decent.
        ratio_score = clamp(min(ratio / 3.0, 1.0))
    elif backend_counts["Fast"] > 0:
        ratio_score = 1.0  # Slow got nothing, Fast got some = great
    else:
        ratio_score = 0.0

    ordering_score = 0.6 if ordering_correct else 0.0
    ordering_score += 0.4 * ratio_score

    # Avg latency (lower = better). Theoretical minimum ≈ 20ms (all to Fast).
    avg_latency = total_latency / total_admitted if total_admitted else 150.0
    # 20ms = score 1.0, 100ms = score 0.2, 150ms = score 0.0
    latency_score = clamp(1.0 - (avg_latency - 20) / 130)

    # Zero shedding (no faults, so shedding = bad)
    shed_rate = total_shed / total_requests if total_requests else 0
    no_shed_score = clamp(1.0 - shed_rate * 5)

    score = 0.4 * ordering_score + 0.3 * latency_score + 0.3 * no_shed_score

    return ScenarioResult(
        name="asymmetric",
        score=clamp(score),
        weight=1.0,
        details={
            "backend_counts": backend_counts,
            "ordering_correct": ordering_correct,
            "avg_latency_ms": round(avg_latency, 2),
            "shed_rate": round(shed_rate, 4),
        },
    )


# ---------------------------------------------------------------------------
# Main: import implementation, run all scenarios, output JSON
# ---------------------------------------------------------------------------

ALL_SCENARIOS = [
    scenario_steady_state,
    scenario_degradation_detection,
    scenario_priority_protection,
    scenario_recovery_smoothness,
    scenario_cascading_failure,
    scenario_flapping,
    scenario_asymmetric,
]


def run_all(lb_class, seed: int) -> dict:
    results = []
    for scenario_fn in ALL_SCENARIOS:
        try:
            result = scenario_fn(lb_class, seed)
        except Exception as e:
            result = ScenarioResult(
                name=scenario_fn.__name__.replace("scenario_", ""),
                score=0.0,
                weight=1.0,
                error=f"{type(e).__name__}: {e}\n{traceback.format_exc()}",
            )
        results.append(result)

    # Weighted aggregate
    total_weight = sum(r.weight for r in results)
    weighted_sum = sum(r.score * r.weight for r in results)
    aggregate = (weighted_sum / total_weight * 100) if total_weight > 0 else 0

    return {
        "aggregate_score": round(aggregate, 2),
        "scenarios": [
            {
                "name": r.name,
                "score": round(r.score, 4),
                "weight": r.weight,
                "weighted_contribution": round(r.score * r.weight / total_weight * 100, 2),
                "details": r.details,
                **({"error": r.error} if r.error else {}),
            }
            for r in results
        ],
    }


def main():
    parser = argparse.ArgumentParser(description="Load Balancer Benchmark")
    parser.add_argument("--workspace", required=True, help="Path to workspace containing load_balancer/ module")
    parser.add_argument("--output", required=True, help="Path to write JSON results")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for determinism")
    args = parser.parse_args()

    workspace = Path(args.workspace).resolve()

    # Add workspace to Python path so we can import load_balancer
    sys.path.insert(0, str(workspace))

    # Also add contracts dir for types.py fallback
    contracts_dir = Path(__file__).resolve().parent.parent / "contracts" / "01_load_balancer"
    if contracts_dir.exists():
        # The types.py should already be in workspace/load_balancer/types.py
        # but add contracts parent as fallback
        pass

    try:
        mod = importlib.import_module("load_balancer")
        lb_class = getattr(mod, "LoadBalancer")
    except Exception as e:
        error_result = {
            "aggregate_score": 0.0,
            "error": f"Failed to import LoadBalancer: {type(e).__name__}: {e}\n{traceback.format_exc()}",
            "scenarios": [],
        }
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps(error_result, indent=2))
        print(f"IMPORT ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Benchmarking: {workspace}")
    print(f"LoadBalancer class: {lb_class}")
    print(f"Seed: {args.seed}")

    results = run_all(lb_class, args.seed)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(results, indent=2))

    print(f"\nAggregate score: {results['aggregate_score']}/100")
    for s in results["scenarios"]:
        status = "ERROR" if "error" in s else f"{s['score']:.2f}"
        print(f"  {s['name']:30s} {status:>8s}  (weight={s['weight']}, contribution={s['weighted_contribution']})")

    print(f"\nResults written to: {args.output}")


if __name__ == "__main__":
    main()
