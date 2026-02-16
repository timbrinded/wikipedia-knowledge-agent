#!/usr/bin/env bash
set -euo pipefail

# Collect quantitative metrics from experiment results.
#
# For each problem × condition, extracts:
#   - Duration (seconds)
#   - Number of turns / tool calls
#   - Lines of code produced
#   - Token usage (input/output)
#   - Wikipedia tool calls (for non-control conditions)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
STATS_FILE="$RESULTS_DIR/stats.tsv"

echo "=== Collecting experiment statistics ==="

# Header
printf "problem\tcondition\tduration_s\tturns\ttool_calls\twiki_searches\tlines_of_code\tinput_tokens\toutput_tokens\n" > "$STATS_FILE"

for problem_dir in "$RESULTS_DIR"/*/; do
    problem=$(basename "$problem_dir")
    [ -d "$problem_dir" ] || continue
    # Skip non-problem dirs
    [ "$problem" = "stats.tsv" ] && continue

    for condition_dir in "$problem_dir"/*/; do
        condition=$(basename "$condition_dir")
        [ -d "$condition_dir" ] || continue
        [ -f "$condition_dir/done" ] || continue

        # Duration from meta.json
        duration=$(jq -r '.duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")

        # Parse Claude Code JSON output for stats
        output_file="$condition_dir/output.json"
        if [ -f "$output_file" ]; then
            # Claude Code --output-format json provides structured data
            turns=$(jq -r '.num_turns // 0' "$output_file" 2>/dev/null || echo "0")
            input_tokens=$(jq -r '.usage.input_tokens // 0' "$output_file" 2>/dev/null || echo "0")
            output_tokens=$(jq -r '.usage.output_tokens // 0' "$output_file" 2>/dev/null || echo "0")

            # Count tool calls from the conversation
            tool_calls=$(jq '[.messages[]? | select(.role == "assistant") | .tool_calls[]?] | length' "$output_file" 2>/dev/null || echo "0")

            # Count Wikipedia-specific searches (grep for data/index or data/articles in tool calls)
            wiki_searches=$(jq -r '[.messages[]? | select(.role == "assistant") | .tool_calls[]? | .input // "" | select(test("data/(index|articles)"))] | length' "$output_file" 2>/dev/null || echo "0")
        else
            turns=0; input_tokens=0; output_tokens=0; tool_calls=0; wiki_searches=0
        fi

        # Count lines of code in workspace
        workspace="$condition_dir/workspace"
        if [ -d "$workspace" ]; then
            lines_of_code=$(find "$workspace" -name "*.py" -not -path "*/data/*" -not -path "*/.claude/*" -exec cat {} + 2>/dev/null | wc -l || echo "0")
        else
            lines_of_code=0
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$problem" "$condition" "$duration" "$turns" "$tool_calls" \
            "$wiki_searches" "$lines_of_code" "$input_tokens" "$output_tokens" \
            >> "$STATS_FILE"
    done
done

echo ""
echo "Stats written to: $STATS_FILE"
echo ""
echo "=== Summary ==="
column -t -s$'\t' "$STATS_FILE"
