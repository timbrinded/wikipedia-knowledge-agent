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
SKILL_DIR="$PROJECT_DIR/skill"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"

# Configurable
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PROBLEMS="${PROBLEMS:-$(ls "$PROBLEMS_DIR"/*.md | sort)}"
CONDITIONS="${CONDITIONS:-control explicit subtle}"

# Preambles for each condition
PREAMBLE_CONTROL=""
PREAMBLE_EXPLICIT="You have access to the entirety of English Wikipedia stored locally as plain text files. If it would help you solve this problem, feel free to search for relevant knowledge — biology, mathematics, history, physics, philosophy, or any other domain. Use ripgrep to search:
- Titles: rg -i \"<query>\" data/index/titles.txt
- Content: rg -i \"<query>\" data/articles/
- Read article: find path via rg -m1 \"^<slug>\" data/index/paths.txt | cut -f3, then cat it

"
PREAMBLE_SUBTLE=""

echo "=== Wikipedia Knowledge Agent — Experiment Runner ==="
echo "Problems:   $(echo "$PROBLEMS" | wc -w | tr -d ' ')"
echo "Conditions: $CONDITIONS"
echo "Results:    $RESULTS_DIR"
echo ""

# Verify Wikipedia data exists for non-control conditions
if [[ "$CONDITIONS" == *"explicit"* ]] || [[ "$CONDITIONS" == *"subtle"* ]]; then
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
            full_prompt="$prompt"
            ;;
        explicit)
            full_prompt="${PREAMBLE_EXPLICIT}${prompt}"
            ;;
        subtle)
            # For subtle: we install the skill but don't mention it in the prompt.
            # The agent can discover the tools via SKILL.md in the workspace.
            full_prompt="$prompt"
            ;;
    esac

    # Set up workspace
    # For subtle condition: copy skill file into workspace so agent can find it
    if [ "$condition" = "subtle" ]; then
        cp "$SKILL_DIR/SKILL.md" "$workdir/.claude/SKILL.md" 2>/dev/null || {
            mkdir -p "$workdir/.claude"
            cp "$SKILL_DIR/SKILL.md" "$workdir/.claude/SKILL.md"
        }
    fi

    # For explicit/subtle: symlink data directory
    if [ "$condition" != "control" ]; then
        ln -sfn "$DATA_DIR" "$workdir/data"
    fi

    echo "  RUN  $problem_name/$condition"
    local start_time
    start_time=$(date +%s)

    # Run Claude Code non-interactively
    # Capture stdout, stderr, and exit code
    cd "$workdir"
    $CLAUDE_CMD -p "$full_prompt" \
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
