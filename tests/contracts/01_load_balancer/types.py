"""
Load Balancer Contract — shared types and abstract base class.

This file is copied into the agent's workspace before it runs.
The agent imports from it and must NOT modify it.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import IntEnum
from typing import Protocol, runtime_checkable


class Priority(IntEnum):
    """Request priority levels. Higher value = higher priority."""

    BACKGROUND = 1
    NORMAL = 2
    CRITICAL = 3


@dataclass(frozen=True)
class Request:
    """An incoming request to be routed by the load balancer."""

    id: int
    priority: Priority
    tick: int  # current simulation tick


@dataclass
class Response:
    """Result of handling a request."""

    request_id: int
    admitted: bool  # routed to a backend?
    success: bool  # backend processed successfully?
    backend_name: str  # "" if shed
    latency_ms: float  # 0.0 if shed
    shed: bool = False  # explicitly load-shed?


@runtime_checkable
class BackendHandle(Protocol):
    """
    Opaque handle to a backend server.

    The load balancer can only interact with backends through these methods.
    It CANNOT read internal state like .alive, .latency_ms, or .error_rate.
    """

    @property
    def name(self) -> str:
        """Unique name identifying this backend."""
        ...

    def send_request(self) -> tuple[bool, float]:
        """
        Send a request to this backend.

        Returns:
            (success, latency_ms) — success=False means the backend failed
            to process the request. latency_ms reflects actual response time.
        """
        ...

    def health_probe(self) -> tuple[bool, float]:
        """
        Send a health check probe to this backend.

        Returns:
            (reachable, latency_ms) — reachable=False means the backend
            did not respond to the probe. Cheaper than send_request().
        """
        ...


class AbstractLoadBalancer(ABC):
    """
    Abstract base class that all load balancer implementations must subclass.

    Lifecycle per simulation tick:
        1. tick() is called once
        2. handle_request() is called N times (once per incoming request)
    """

    @abstractmethod
    def __init__(self, backends: list[BackendHandle]) -> None:
        """
        Initialize the load balancer with a list of backend handles.

        Args:
            backends: Opaque handles to backend servers. Use send_request()
                      and health_probe() to interact with them.
        """
        ...

    @abstractmethod
    def handle_request(self, request: Request) -> Response:
        """
        Route or shed a single request.

        Args:
            request: The incoming request with id, priority, and current tick.

        Returns:
            Response indicating whether the request was admitted, succeeded,
            which backend handled it, and the latency.
        """
        ...

    @abstractmethod
    def tick(self) -> None:
        """
        Called once at the start of each simulation tick.

        Use this for periodic maintenance: health checks, stats updates,
        recovery logic, etc.
        """
        ...
