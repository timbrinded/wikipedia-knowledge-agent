# Problem 2: Smart Cache Eviction for Social Media Feed

Design and implement a cache eviction strategy in Python for a social media feed. The cache should be smarter than simple LRU — it should account for the fact that some content is more likely to be re-accessed based on recency, popularity, and the user's personal engagement patterns.

## Requirements

- Fixed-size cache (configurable max entries)
- Each cached item has: content_id, timestamp, access_count, engagement_score
- Eviction should consider multiple signals, not just recency or frequency alone
- Handle "viral" content (sudden spikes in access) differently from steady-state popular content
- Provide a simulation with synthetic access patterns showing the strategy outperforms naive LRU

## Deliverable

A working Python implementation with:
1. The cache with your custom eviction strategy
2. A baseline LRU cache for comparison
3. A simulation generating realistic access patterns (zipf distribution, viral spikes, temporal decay)
4. Hit rate comparison between your strategy and LRU

Write all code to a `cache_eviction/` directory.
