# Problem 10: Add Pagination to API Endpoint

Implement a simple REST API in Python (using Flask or any lightweight framework) that serves a list of items with cursor-based pagination.

## Requirements

- `GET /items` — returns paginated items
- Query params: `cursor` (opaque string, optional), `limit` (int, default 20, max 100)
- Response format:
  ```json
  {
    "items": [...],
    "next_cursor": "abc123",
    "has_more": true
  }
- Cursor-based (not offset-based) — stable under insertions/deletions
- Seed the API with 1000 sample items on startup
- Include a test script that paginates through all items and verifies:
  - All items are returned exactly once
  - No duplicates or gaps
  - Ordering is consistent

## Deliverable

Write all code to a `pagination/` directory.
