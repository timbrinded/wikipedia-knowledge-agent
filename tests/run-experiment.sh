#!/usr/bin/env bash
set -euo pipefail

# Run the Wikipedia Knowledge Agent experiment.
#
# Executes each test problem under three conditions:
#   1. control  — no Wikipedia access
#   2. explicit — Wikipedia access + told to use it
#   3. subtle   — Wikipedia access available but not highlighted
#
# Uses Claude Code in non-interactive mode (-p flag).
# Outputs saved to results/<problem>/<condition>/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROBLEMS_DIR="$SCRIPT_DIR/problems"
RESULTS_DIR="$PROJECT_DIR/results"
PLUGIN_DIR="$PROJECT_DIR"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"

# Configurable
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PROBLEMS="${PROBLEMS:-$(ls "$PROBLEMS_DIR"/*.md | sort)}"
CONDITIONS="${CONDITIONS:-control explicit subtle reflective}"

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

# Preambles for each condition
PREAMBLE_CONTROL=""
PREAMBLE_EXPLICIT="IMPORTANT: You have access to the entirety of English Wikipedia stored locally as plain text files (~6.8M articles). You MUST consult Wikipedia before designing your solution.

Before writing any code:
1. Use the wiki-lookup skill to research the core concepts of the problem domain (algorithms, data structures, known approaches).
2. Spawn the wiki-explorer agent to find cross-domain structural analogues — it traverses biology, ecology, economics, physics, mathematics, philosophy, and other fields to find non-obvious patterns that map to your problem. The best solutions often come from insights outside the immediate domain.
3. Let what you learn from Wikipedia inform your design. Reference specific concepts or analogues in code comments where they influenced your approach.

For quick lookups, search directly:
- Titles: rg -i \"<query>\" data/index/titles.txt
- Categories: rg -i \"<query>\" data/index/categories.txt
- Content: rg -i \"<query>\" data/articles/
- Read article: find path via rg -m1 \"^<slug>\" data/index/paths.txt | cut -f3, then read it

"
PREAMBLE_SUBTLE=""

PREAMBLE_REFLECTIVE="You are a historically-informed engineer. You don't just write correct code — you think about regret. Before committing to an approach, you consider: what has been tried before? What failed? Is this complexity proportionate to the problem?

You have a wiki-reflector agent available. It has access to the entirety of English Wikipedia and thinks in terms of historical precedent, cautionary tales, proportionality, and track records. Use it when your problem has meaningful historical context — when knowing what others tried (and what went wrong) would change your approach.

For straightforward mechanical tasks (parsers, data structures, standard algorithms), skip the reflection and implement directly. Not every problem benefits from historical context, and you should be comfortable proceeding without it.

For quick lookups, search directly:
- Titles: rg -i \"<query>\" data/index/titles.txt
- Categories: rg -i \"<query>\" data/index/categories.txt
- Content: rg -i \"<query>\" data/articles/
- Read article: find path via rg -m1 \"^<slug>\" data/index/paths.txt | cut -f3, then read it

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

    # Read the problem prompt
    local prompt
    prompt=$(cat "$problem_file")

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
    cd "$workdir"
    CLAUDECODE= $CLAUDE_CMD -p "$full_prompt" \
        --dangerously-skip-permissions \
        $extra_args \
        --output-format json \
        > "$outdir/output.json" \
        2> "$outdir/stderr.log" \
        || true

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
