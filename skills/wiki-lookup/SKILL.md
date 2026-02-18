---
name: wiki-lookup
description: |-
  This skill should be used when the user asks to "look up a Wikipedia article", "search Wikipedia for", "find the Wikipedia page on", "check Wikipedia about", or needs a quick fact or single article from the local Wikipedia data. For quick lookups and single-article reads — not for cross-domain exploration.
---

# Wikipedia Quick Lookup

Quick lookup skill for the local Wikipedia data lake (~20K articles stored as plain text).

## How to Search

### Find articles by title
```bash
rg -i "<query>" data/index/titles.txt | head -20
```

### Find articles by category
```bash
rg -i "<query>" data/index/categories.txt | head -20
```

### Word-boundary search (avoid partial matches)
```bash
rg -i -w "<query>" data/index/titles.txt | head -20
```
Use `-w` when a short query returns too many irrelevant hits — it matches whole words only.

### OR search (synonyms, related terms)
```bash
rg -i -e "<term1>" -e "<term2>" data/index/titles.txt | head -20
```
Search for multiple terms at once. Great for synonyms or when the article title might use different phrasing.

### Read a specific article

Find the path first, then read it:
```bash
rg -m1 "^<slug>\t" data/index/paths.txt | cut -f3
```
Then use the Read tool on the returned path.

### Preview an article (without reading the whole thing)
```bash
head -50 data/articles/<prefix>/<slug>.txt
```
Scan the opening to decide if the article is worth a full read.

### Search across article content
```bash
rg -l -i "<query>" data/articles/ | head -20
```
Returns file paths of matching articles. Narrow with title/category search first — full-text is powerful but slower.

### Content snippets (see matches in context)
```bash
rg -i -m2 -C1 "<query>" data/articles/<prefix>/<slug>.txt
```
`-m2` limits to first 2 matches, `-C1` shows 1 line of context around each. Useful for checking relevance before a full read.

### Count matches for relevance ranking
```bash
rg -i -c "<query>" data/articles/ | sort -t: -k2 -nr | head -10
```
Articles with more mentions are likely more relevant.

### AND search (both terms must appear)
```bash
rg -l -i "<term1>" data/articles/ | xargs rg -l -i "<term2>" | head -10
```

### Fixed-string search (disable regex)
```bash
rg -F -i "<literal>" data/index/titles.txt
```
Use `-F` when your query contains regex-special characters (dots, parens, brackets).

## Worked Example — Simple Lookup

**Task**: "What does Wikipedia say about circuit breaker patterns?"

1. Search titles: `rg -i "circuit.breaker" data/index/titles.txt`
2. Find path: `rg -m1 "^circuit-breaker\t" data/index/paths.txt | cut -f3`
3. Read the article with the Read tool
4. Return the relevant information

## Worked Example — Narrowing Down Results

**Task**: "Find information about ant colony optimization"

1. Search titles: `rg -i "ant" data/index/titles.txt | head -20` — too many results (elephant, antenna, etc.)
2. Narrow with word boundary: `rg -i -w "ant" data/index/titles.txt | head -20` — better but still noisy
3. Try more specific: `rg -i "ant colony" data/index/titles.txt` — found it
4. If title search fails, try content: `rg -l -i "ant colony optimization" data/articles/ | head -5`
5. Preview before reading: `head -50 data/articles/an/ant-colony-optimization.txt`
6. Full read with the Read tool

## Search Strategy

1. **Titles first** — instant and gives you article slugs directly
2. **Preview before full read** — `head -50` saves time on irrelevant articles
3. **Narrow before broadening** — start specific, add `-w` if too many results, broaden with `-e` synonyms if too few
4. **Content search last** — powerful but slower; use after title/category search narrows scope

## When to Escalate

If the task requires **cross-domain connections**, **non-obvious structural analogues**, or **synthesising insights across multiple articles from different fields** — spawn the `wiki-explorer` agent instead. That agent is purpose-built for lateral knowledge exploration.

Examples of when to escalate:
- "Find biological analogues to our load balancing problem"
- "What can ecology teach us about system resilience?"
- "Search across domains for patterns similar to consensus algorithms"
