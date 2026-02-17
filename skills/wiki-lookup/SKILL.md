---
name: wiki-lookup
description: |-
  This skill should be used when the user asks to "look up a Wikipedia article", "search Wikipedia for", "find the Wikipedia page on", "check Wikipedia about", or needs a quick fact or single article from the local Wikipedia data. For quick lookups and single-article reads — not for cross-domain exploration.
---

# Wikipedia Quick Lookup

Quick lookup skill for the local Wikipedia data lake (~6.8M articles stored as plain text).

## How to Search

### Find articles by title

```bash
rg -i "<query>" data/index/titles.txt | head -20
```

### Find articles by category

```bash
rg -i "<query>" data/index/categories.txt | head -20
```

### Read a specific article

Find the path first, then read it:

```bash
rg -m1 "^<slug>\t" data/index/paths.txt | cut -f3
```

Then use the Read tool on the returned path.

### Search across article content

```bash
rg -l -i "<query>" data/articles/ | head -20
```

Narrow with title/category search first — full-text search is powerful but slower.

## Worked Example

**Task**: "What does Wikipedia say about circuit breaker patterns?"

1. Search titles: `rg -i "circuit.breaker" data/index/titles.txt`
2. Find path: `rg -m1 "^circuit-breaker\t" data/index/paths.txt | cut -f3`
3. Read the article with the Read tool
4. Return the relevant information

## When to Escalate

If the task requires **cross-domain connections**, **non-obvious structural analogues**, or **synthesising insights across multiple articles from different fields** — spawn the `wiki-explorer` agent instead. That agent is purpose-built for lateral knowledge exploration.

Examples of when to escalate:
- "Find biological analogues to our load balancing problem"
- "What can ecology teach us about system resilience?"
- "Search across domains for patterns similar to consensus algorithms"
