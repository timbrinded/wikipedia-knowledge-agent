# Wikipedia Knowledge Agent

**Does giving a coding agent access to all of human knowledge change how it solves problems?**

An experiment in lateral knowledge transfer. We give [Claude Code](https://docs.anthropic.com/en/docs/claude-code) access to the entirety of Wikipedia (~6.8M articles) via ripgrep, then test whether cross-domain knowledge — biology, history, philosophy, materials science — changes how it approaches coding problems.

The hypothesis: humans don't solve problems using only domain knowledge. A biologist who codes brings different intuitions than a pure CS grad. What if an agent armed with all of human knowledge finds analogies and makes lateral connections a pure-coding agent wouldn't?

## The Experiment

We run Claude Code in non-interactive mode (`-p` flag) against a test suite of coding problems under three conditions:

| Condition | Wikipedia Access | Prompting |
|-----------|-----------------|-----------|
| **Control** | ❌ None | Standard coding prompt |
| **Explicit** | ✅ Full | "You have access to Wikipedia — use it if helpful" |
| **Subtle** | ✅ Full | Tools available but not highlighted |

Same prompts across all conditions. We compare:

- **Quantitative**: Turns, tokens, lines of code, time, tool calls
- **LLM-as-Judge**: Blinded comparison — which solution is better, more creative, more robust?
- **Human Review**: Spot-check interesting divergences

## Test Suite

### Problems where lateral knowledge could help

| # | Problem | Potential cross-domain connections |
|---|---------|-----------------------------------|
| 1 | Design a load balancer that gracefully degrades | Biological resilience, ecological redundancy |
| 2 | Design a cache eviction strategy for a social media feed | Memory research, attention/cognition science |
| 3 | Build a consensus algorithm for distributed nodes | Political science, voting theory, swarm behaviour |
| 4 | Design a recommendation system that avoids filter bubbles | Sociology, epistemology, information theory |
| 5 | Optimise delivery routing for a fleet | Ant colony optimisation, logistics, graph theory |

### Control problems (lateral knowledge unlikely to help)

| # | Problem | Why it's a control |
|---|---------|-------------------|
| 6 | Fix a race condition in concurrent code | Pure code reasoning |
| 7 | Implement a binary search tree in Python | Textbook algorithm |
| 8 | Write a parser for a CSV format | Mechanical task |
| 9 | Debug a failing test | Pure code reasoning |
| 10 | Add pagination to an API endpoint | Mechanical task |

## Project Structure

```
├── README.md
├── setup/
│   ├── download-wikipedia.sh      # Download & extract Wikipedia dump
│   └── build-index.sh             # Build title/category indexes
├── skill/
│   ├── SKILL.md                   # Claude Code skill (progressive disclosure)
│   └── instructions.md            # Skill instructions for the agent
├── tests/
│   ├── problems/                  # Test problem definitions
│   │   ├── 01-load-balancer.md
│   │   ├── 02-cache-eviction.md
│   │   └── ...
│   └── run-experiment.sh          # Test harness
├── eval/
│   ├── collect-stats.sh           # Quantitative metrics extraction
│   └── llm-judge.sh               # LLM-as-judge evaluation
└── results/                       # Experiment outputs
    ├── visualize.ipynb            # Results charts & analysis notebook
    └── stats.tsv                  # Quantitative metrics per run
```

## Setup

### Prerequisites

- [uv](https://docs.astral.sh/uv/) — Python package & project manager
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) installed
- ~100GB free disk space for Wikipedia dump
- Anthropic API key (for Claude Code and LLM judge)

### 1. Install dependencies

```bash
uv sync
```

Creates a `.venv` and installs Python dependencies (WikiExtractor, etc.). All Python execution in this project goes through `uv run`.

### 2. Download Wikipedia

```bash
./setup/download-wikipedia.sh
```

Downloads the latest English Wikipedia dump and extracts it to flat text files (one per article). This takes several hours depending on your connection.

### 3. Build indexes

```bash
./setup/build-index.sh
```

Builds greppable title and category indexes for fast lookup.

### 4. Run the experiment

```bash
./tests/run-experiment.sh
```

Runs all test problems across all three conditions and saves outputs to `results/`.

### 5. Evaluate

```bash
./eval/collect-stats.sh    # Quantitative metrics
./eval/llm-judge.sh        # LLM-as-judge comparison
```

### 6. Visualise results

```bash
uv run jupyter lab results/visualize.ipynb
```

Opens a notebook with charts covering duration, token usage, permission denials, cost breakdown, and a summary heatmap across all conditions and problem types.

## How Wikipedia Access Works

The agent gets a Claude Code skill with these tools:

- **`search_titles`** — ripgrep across article titles (fast, ~6.8M entries)
- **`search_categories`** — ripgrep across category assignments
- **`read_article`** — read a specific article by title
- **`grep_knowledge`** — ripgrep across all article content (slow but powerful)

The skill uses progressive disclosure: the agent knows it has access to a knowledge base and basic search capabilities. It decides when and how to use them.

## What We're Looking For

The interesting question isn't "does Wikipedia make code better" — it's **does the agent reach for non-programming knowledge unprompted, and when it does, does it produce meaningfully different solutions?**

We're looking for:
- Lateral analogies (e.g., using ecological resilience patterns for system design)
- Novel framings that a pure-coding agent wouldn't generate
- Whether cross-domain knowledge leads to more robust or creative solutions
- Cost/benefit: does the extra knowledge add noise or signal?

## License

MIT
