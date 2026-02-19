## Implementation Contract

A `types.py` file has been placed in `load_balancer/types.py`. It defines the types and abstract base class you MUST use.

### Rules

1. **Import from `types.py`** — use `from load_balancer.types import ...`. Do NOT modify `types.py`.
2. **Subclass `AbstractLoadBalancer`** — your main class MUST be named `LoadBalancer` and inherit from `AbstractLoadBalancer`.
3. **Export from `__init__.py`** — your `load_balancer/__init__.py` MUST export `LoadBalancer` so that `from load_balancer import LoadBalancer` works.
4. **BackendHandle is opaque** — interact with backends ONLY through `send_request()` and `health_probe()`. Do NOT access internal attributes, do NOT subclass or wrap BackendHandle with your own class that reads hidden state.
5. **Lifecycle** — each simulation tick: `tick()` is called once, then `handle_request()` is called once per incoming request.

### What's Fixed (do not change)

- `Priority` enum: BACKGROUND=1, NORMAL=2, CRITICAL=3
- `Request` dataclass: `id`, `priority`, `tick`
- `Response` dataclass: `request_id`, `admitted`, `success`, `backend_name`, `latency_ms`, `shed`
- `BackendHandle` protocol: `name` property, `send_request()`, `health_probe()`
- `AbstractLoadBalancer` ABC: `__init__(backends)`, `handle_request(request)`, `tick()`

### What's Free (your design choices)

- Routing algorithm (round-robin, least-connections, weighted, etc.)
- Health tracking strategy (how you interpret probe/request results)
- Load shedding logic (when and what to shed)
- Recovery mechanism (how you ramp backends back up)
- Internal state, helper classes, additional files
- Any additional methods on your `LoadBalancer` class
