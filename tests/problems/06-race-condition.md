# Problem 6: Fix the Race Condition

The following Python code has a race condition in its concurrent counter implementation. Find and fix the bug, then add a test that proves the fix works.

```python
import threading
import time

class BankAccount:
    def __init__(self, balance=1000):
        self.balance = balance

    def withdraw(self, amount):
        current = self.balance
        time.sleep(0.001)  # simulate processing
        if current >= amount:
            self.balance = current - amount
            return True
        return False

    def deposit(self, amount):
        current = self.balance
        time.sleep(0.001)  # simulate processing
        self.balance = current + amount

def transfer(from_account, to_account, amount):
    if from_account.withdraw(amount):
        to_account.deposit(amount)

# Simulation: 100 concurrent transfers of $10 between two accounts
account_a = BankAccount(1000)
account_b = BankAccount(1000)

threads = []
for _ in range(100):
    t1 = threading.Thread(target=transfer, args=(account_a, account_b, 10))
    t2 = threading.Thread(target=transfer, args=(account_b, account_a, 10))
    threads.extend([t1, t2])

for t in threads:
    t.start()
for t in threads:
    t.join()

# Total should always be $2000
total = account_a.balance + account_b.balance
print(f"Account A: ${account_a.balance}")
print(f"Account B: ${account_b.balance}")
print(f"Total: ${total} (expected: $2000)")
assert total == 2000, f"Money appeared/disappeared! Total is ${total}"
```

## Deliverable

Write the fixed code and test to a `race_condition/` directory.
