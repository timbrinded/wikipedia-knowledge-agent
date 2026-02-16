# Problem 9: Debug the Failing Test

The following code implements a simple task scheduler, but two tests are failing. Find the bugs and fix them. Do not change the tests — fix the implementation.

```python
import heapq
from dataclasses import dataclass, field
from typing import Optional
import time

@dataclass(order=True)
class Task:
    priority: int
    name: str = field(compare=False)
    created_at: float = field(compare=False, default_factory=time.time)
    dependencies: list = field(compare=False, default_factory=list)

class TaskScheduler:
    def __init__(self):
        self.tasks = []
        self.completed = set()

    def add_task(self, name: str, priority: int, dependencies: list = None):
        task = Task(priority=priority, name=name, dependencies=dependencies or [])
        heapq.heappush(self.tasks, task)

    def get_next(self) -> Optional[Task]:
        """Get the highest priority task whose dependencies are all completed."""
        skipped = []
        result = None

        while self.tasks:
            task = heapq.heappop(self.tasks)
            deps_met = all(d in self.completed for d in task.dependencies)
            if deps_met:
                result = task
                break
            skipped.append(task)

        # Put skipped tasks back — BUG: loses heap ordering
        self.tasks = skipped + self.tasks
        return result

    def complete(self, task_name: str):
        self.completed.add(task_name)

    def pending_count(self) -> int:
        return len(self.tasks)


# === TESTS (do not modify) ===

def test_basic_priority():
    s = TaskScheduler()
    s.add_task("low", priority=10)
    s.add_task("high", priority=1)
    s.add_task("medium", priority=5)

    t = s.get_next()
    assert t.name == "high", f"Expected 'high', got '{t.name}'"
    s.complete(t.name)

    t = s.get_next()
    assert t.name == "medium", f"Expected 'medium', got '{t.name}'"
    s.complete(t.name)

    t = s.get_next()
    assert t.name == "low", f"Expected 'low', got '{t.name}'"

def test_dependencies():
    s = TaskScheduler()
    s.add_task("deploy", priority=1, dependencies=["build", "test"])
    s.add_task("build", priority=2)
    s.add_task("test", priority=3, dependencies=["build"])

    # First should be "build" (highest available priority with no deps)
    t = s.get_next()
    assert t.name == "build", f"Expected 'build', got '{t.name}'"
    s.complete(t.name)

    # Next should be "test" (dependency on build now met)
    t = s.get_next()
    assert t.name == "test", f"Expected 'test', got '{t.name}'"
    s.complete(t.name)

    # Finally "deploy" (both deps met)
    t = s.get_next()
    assert t.name == "deploy", f"Expected 'deploy', got '{t.name}'"

def test_pending_count():
    s = TaskScheduler()
    s.add_task("a", 1)
    s.add_task("b", 2)
    assert s.pending_count() == 2
    s.get_next()
    assert s.pending_count() == 1

if __name__ == "__main__":
    test_basic_priority()
    print("✓ test_basic_priority passed")
    test_dependencies()
    print("✓ test_dependencies passed")
    test_pending_count()
    print("✓ test_pending_count passed")
    print("\nAll tests passed!")
```

## Deliverable

Write the fixed code to a `debug_scheduler/` directory.
