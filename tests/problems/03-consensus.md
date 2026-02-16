# Problem 3: Consensus Algorithm for Distributed Nodes

Design and implement a consensus algorithm in Python for a network of distributed nodes that need to agree on a shared value. Nodes can fail, messages can be delayed, and the network can partition.

## Requirements

- N nodes that communicate via message passing
- Nodes can propose values and must eventually agree on one
- Tolerate up to f = (N-1)/3 byzantine (arbitrarily faulty) nodes
- Implement a simulation of the message-passing network with configurable delays and failures
- Demonstrate consensus being reached under normal conditions and under adversarial conditions

## Deliverable

A working Python simulation with:
1. The consensus protocol implementation
2. A simulated network layer with configurable message delay and loss
3. Byzantine fault injection (nodes that lie, delay, or send conflicting messages)
4. Demonstration runs showing consensus achieved despite faults

Write all code to a `consensus/` directory.
