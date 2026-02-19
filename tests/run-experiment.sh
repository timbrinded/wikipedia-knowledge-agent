#!/usr/bin/env bash
set -euo pipefail

# Run the Wikipedia Knowledge Agent experiment.
#
# Executes each test problem under multiple conditions:
#   Original:  control, explicit, subtle, reflective
#   Wave 2:    flaneur, consilience, biomimetic, contrarian
#
# Uses Claude Code in non-interactive mode (-p flag).
# Outputs saved to results/<problem>/<condition>/
#
# Run specific conditions:  CONDITIONS="flaneur consilience" ./tests/run-experiment.sh
# Run specific problems:    PROBLEMS="tests/problems/01-load-balancer.md" ./tests/run-experiment.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROBLEMS_DIR="$SCRIPT_DIR/problems"
RESULTS_DIR="$PROJECT_DIR/results"
PLUGIN_DIR="$PROJECT_DIR"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"

# Configurable
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PROBLEMS="${PROBLEMS:-$(ls "$PROBLEMS_DIR"/*.md | sort)}"
CONDITIONS="${CONDITIONS:-control explicit subtle reflective flaneur consilience biomimetic contrarian}"

# Build extra Claude CLI flags for a given condition
claude_extra_args() {
    local condition="$1"
    local workdir="$2"
    local args=""
    if [ "$condition" != "control" ]; then
        args="--plugin-dir $PLUGIN_DIR"
    fi
    echo "$args"
}

# Universal preamble — ensures the agent writes code directly in non-interactive mode
PREAMBLE_UNIVERSAL="You are running in non-interactive mode. Implement the solution fully by yourself. Do NOT use AskUserQuestion or ask for user input — write all code directly. Do NOT enter plan mode. Just implement the solution and write the files.

"

# Shared search instructions — used by multiple preambles below
WIKI_SEARCH_INSTRUCTIONS="For quick lookups, search directly:
- Titles: rg -i \"<query>\" data/index/titles.txt | head -20
- Categories: rg -i \"<query>\" data/index/categories.txt | head -20
- Word-boundary (avoid partial matches): rg -i -w \"<query>\" data/index/titles.txt
- OR search (synonyms): rg -i -e \"<term1>\" -e \"<term2>\" data/index/titles.txt
- Read article: find path via rg -m1 \"^<slug>\t\" data/index/paths.txt | cut -f3, then read it
- Preview article: head -50 data/articles/<prefix>/<slug>.txt
- Content search (files): rg -l -i \"<query>\" data/articles/ | head -20
- Content snippets: rg -i -m2 -C1 \"<query>\" data/articles/<prefix>/<slug>.txt

Strategy: search titles first (instant), preview with head -50 before reading fully, narrow with -w if too many results, broaden with -e synonyms if too few."

# Preambles for each condition
PREAMBLE_CONTROL=""
PREAMBLE_EXPLICIT="IMPORTANT: You have access to the entirety of English Wikipedia stored locally as plain text files (~20K articles). You MUST consult Wikipedia before designing your solution.

Before writing any code:
1. Use the wiki-lookup skill to research the core concepts of the problem domain (algorithms, data structures, known approaches).
2. Spawn the wiki-explorer agent to find cross-domain structural analogues — it traverses biology, ecology, economics, physics, mathematics, philosophy, and other fields to find non-obvious patterns that map to your problem. The best solutions often come from insights outside the immediate domain.
3. Let what you learn from Wikipedia inform your design. Reference specific concepts or analogues in code comments where they influenced your approach.

$WIKI_SEARCH_INSTRUCTIONS

"
PREAMBLE_SUBTLE=""

PREAMBLE_REFLECTIVE="You are a historically-informed engineer. You don't just write correct code — you think about regret. Before committing to an approach, you consider: what has been tried before? What failed? Is this complexity proportionate to the problem?

You have a wiki-reflector agent available. It has access to the entirety of English Wikipedia and thinks in terms of historical precedent, cautionary tales, proportionality, and track records. Use it when your problem has meaningful historical context — when knowing what others tried (and what went wrong) would change your approach.

For straightforward mechanical tasks (parsers, data structures, standard algorithms), skip the reflection and implement directly. Not every problem benefits from historical context, and you should be comfortable proceeding without it.

$WIKI_SEARCH_INSTRUCTIONS

"

# --- Wave 2 conditions ---

DENY_ALL_OTHERS="STRICT RULE: Do NOT spawn or use any wiki agent other than the one specified above. Specifically, do NOT use: wiki-explorer, wiki-reflector, wiki-flaneur, wiki-consilience, wiki-biomimetic, or wiki-contrarian — unless it is the one explicitly named in your instructions."

PREAMBLE_FLANEUR="You have access to the entirety of English Wikipedia stored locally as plain text files (~20K articles). Before you start engineering, you MUST let the wiki-flaneur agent take a random walk through Wikipedia.

The flaneur does not search for solutions. It wanders — picking random articles, following curiosity, reading deeply — and only AFTER the walk does it reflect on what might connect to your problem. The best insights come from exposure you didn't plan.

Before writing any code:
1. Spawn the wiki-flaneur agent with the problem statement. Let it walk.
2. Read what it brings back. Let the texture settle.
3. Then — and only then — design and implement your solution. Let whatever resonated from the walk influence your design, even if the connection is loose.

Use ONLY the wiki-flaneur agent. $DENY_ALL_OTHERS

$WIKI_SEARCH_INSTRUCTIONS

"

PREAMBLE_CONSILIENCE="You have access to the entirety of English Wikipedia stored locally as plain text files (~20K articles). You MUST search for convergent evidence before designing your solution.

You have a wiki-consilience agent. It hunts for the same structural pattern appearing independently across 3+ unrelated domains. One analogy is anecdote. Two is suggestive. Three independent convergences is signal — evidence that a pattern is fundamental, not accidental.

Before writing any code:
1. Spawn the wiki-consilience agent with the problem statement.
2. If it finds strong consilience (3+ independent domains converging on the same mechanism), treat that as strong evidence the pattern is fundamental — build on it.
3. If consilience is weak, proceed with standard engineering. Not every problem has a deep structural pattern.

Use ONLY the wiki-consilience agent. $DENY_ALL_OTHERS

$WIKI_SEARCH_INSTRUCTIONS

"

PREAMBLE_BIOMIMETIC="You have access to the entirety of English Wikipedia stored locally as plain text files (~20K articles). You MUST consult biology and ecology before designing your solution.

You have a wiki-biomimetic agent. It looks ONLY at biological and ecological systems — evolution, neuroscience, immunology, ethology, botany, mycology — to find how nature solves the same structural problem. Four billion years of evolution has produced solutions to resource allocation, distributed coordination, fault tolerance, and optimization that often outperform human engineering.

Before writing any code:
1. Spawn the wiki-biomimetic agent with the problem statement.
2. If it finds a biological mechanism that translates well to code, implement it. Not as a metaphor — as an actual algorithm or architecture derived from the biological mechanism.
3. If the biological lens doesn't improve on standard approaches, proceed with standard engineering. The agent will tell you honestly.

Use ONLY the wiki-biomimetic agent. $DENY_ALL_OTHERS

$WIKI_SEARCH_INSTRUCTIONS

"

PREAMBLE_CONTRARIAN="You have access to the entirety of English Wikipedia stored locally as plain text files (~20K articles). Before committing to your first instinct, you MUST stress-test it.

You have a wiki-contrarian agent. It is adversarial — it actively searches for evidence that the obvious approach is WRONG. Historical failures, known limitations, documented anti-patterns, cases where the standard solution lost. Its job is to find reasons NOT to do the thing you were about to do.

Before writing any code:
1. Identify your default approach — the thing you'd build without thinking twice.
2. Spawn the wiki-contrarian agent to stress-test that default.
3. If it finds compelling evidence against your default, reconsider. If the default survives scrutiny, proceed with higher confidence.

Use ONLY the wiki-contrarian agent. $DENY_ALL_OTHERS

$WIKI_SEARCH_INSTRUCTIONS

"

echo "=== Wikipedia Knowledge Agent — Experiment Runner ==="
echo "Problems:   $(echo "$PROBLEMS" | wc -w | tr -d ' ')"
echo "Conditions: $CONDITIONS"
echo "Results:    $RESULTS_DIR"
echo ""

# Verify Wikipedia data exists for non-control conditions
needs_wikipedia=false
for _cond in $CONDITIONS; do
    [ "$_cond" != "control" ] && needs_wikipedia=true
done
if $needs_wikipedia; then
    if [ ! -d "$DATA_DIR/articles" ]; then
        echo "ERROR: Wikipedia data not found at $DATA_DIR/articles"
        echo "Run ./setup/download-wikipedia.sh first."
        exit 1
    fi
    echo "Wikipedia data: $DATA_DIR/articles ($(find "$DATA_DIR/articles" -name "*.txt" | wc -l) articles)"
    echo ""
fi

run_problem() {
    local problem_file="$1"
    local condition="$2"
    local problem_name
    problem_name=$(basename "$problem_file" .md)

    local outdir="$RESULTS_DIR/$problem_name/$condition"
    local workdir="$outdir/workspace"

    # Skip if already done
    if [ -f "$outdir/done" ]; then
        echo "  SKIP $problem_name/$condition (already done)"
        return
    fi

    mkdir -p "$workdir"

    # Copy contract types into workspace if a contract exists for this problem
    local contract_dir="$SCRIPT_DIR/contracts/${problem_name//-/_}"
    if [ -d "$contract_dir" ]; then
        # Derive module dir from problem name: "01-load-balancer" -> "load_balancer"
        local module_dir
        module_dir=$(echo "$problem_name" | sed 's/^[0-9]*-//' | tr '-' '_')
        mkdir -p "$workdir/$module_dir"
        cp "$contract_dir/types.py" "$workdir/$module_dir/types.py"
    fi

    # Read the problem prompt
    local prompt
    prompt=$(cat "$problem_file")

    # Append contract instructions if available
    if [ -f "$contract_dir/README.md" ]; then
        prompt="${prompt}

$(cat "$contract_dir/README.md")"
    fi

    # Build the full prompt based on condition
    local full_prompt
    case "$condition" in
        control)
            full_prompt="${PREAMBLE_UNIVERSAL}${prompt}"
            ;;
        explicit)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_EXPLICIT}${prompt}"
            ;;
        subtle)
            # For subtle: we install the skill but don't mention it in the prompt.
            # The agent can discover the tools via SKILL.md in the workspace.
            full_prompt="${PREAMBLE_UNIVERSAL}${prompt}"
            ;;
        reflective)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_REFLECTIVE}${prompt}"
            ;;
        flaneur)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_FLANEUR}${prompt}"
            ;;
        consilience)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_CONSILIENCE}${prompt}"
            ;;
        biomimetic)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_BIOMIMETIC}${prompt}"
            ;;
        contrarian)
            full_prompt="${PREAMBLE_UNIVERSAL}${PREAMBLE_CONTRARIAN}${prompt}"
            ;;
        *)
            echo "ERROR: Unknown condition '$condition'" >&2
            return 1
            ;;
    esac

    # Set up workspace — symlink Wikipedia data for non-control conditions
    if [ "$condition" != "control" ]; then
        ln -sfn "$DATA_DIR" "$workdir/data"
    fi

    # Build extra CLI flags (--plugin-dir for non-control)
    local extra_args
    extra_args=$(claude_extra_args "$condition" "$workdir")

    echo "  RUN  $problem_name/$condition"
    local start_time
    start_time=$(date +%s)

    # Run Claude Code non-interactively
    # Capture stdout, stderr, and exit code
    # Use subshell to avoid polluting cwd for subsequent iterations
    (cd "$workdir" && \
    CLAUDECODE= $CLAUDE_CMD -p "$full_prompt" \
        --dangerously-skip-permissions \
        $extra_args \
        --output-format json \
        > "$outdir/output.json" \
        2> "$outdir/stderr.log" \
        || true)

    local end_time
    end_time=$(date +%s)
    local duration=$(( end_time - start_time ))

    # Record metadata
    cat > "$outdir/meta.json" << METAEOF
{
    "problem": "$problem_name",
    "condition": "$condition",
    "duration_seconds": $duration,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "claude_cmd": "$CLAUDE_CMD"
}
METAEOF

    touch "$outdir/done"
    echo "  DONE $problem_name/$condition (${duration}s)"
}

# Run all combinations
for problem_file in $PROBLEMS; do
    problem_name=$(basename "$problem_file" .md)
    echo ""
    echo "--- Problem: $problem_name ---"
    for condition in $CONDITIONS; do
        run_problem "$problem_file" "$condition"
    done
done

echo ""
echo "=== Experiment complete ==="
echo "Results in: $RESULTS_DIR"
echo "Run ./eval/collect-stats.sh to gather metrics."
