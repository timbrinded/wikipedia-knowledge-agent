#!/usr/bin/env bash
set -euo pipefail

# Collect quantitative metrics from experiment results.
#
# For each problem × condition, extracts:
#   - Duration (seconds)
#   - Number of turns
#   - Total cost (USD)
#   - Subagent output tokens (haiku model — proxy for wiki-explorer/reflector usage)
#   - Lines of code produced
#   - Token usage (input/output, summed across all models including subagents)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
STATS_FILE="$RESULTS_DIR/stats.tsv"

echo "=== Collecting experiment statistics ==="

# Header
printf "problem\tcondition\tduration_s\tturns\tcost_usd\tsubagent_out_tokens\tlines_of_code\tinput_tokens\toutput_tokens\n" > "$STATS_FILE"

for problem_dir in "$RESULTS_DIR"/*/; do
    problem=$(basename "$problem_dir")
    [ -d "$problem_dir" ] || continue
    # Skip non-problem dirs
    [[ "$problem" == "stats.tsv" || "$problem" == "evaluations" || "$problem" == "visualize.ipynb" ]] && continue

    for condition_dir in "$problem_dir"/*/; do
        condition=$(basename "$condition_dir")
        [ -d "$condition_dir" ] || continue
        [ -f "$condition_dir/done" ] || continue

        # Duration from meta.json
        duration=$(jq -r '.duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")

        # Parse Claude Code JSON output for stats
        # Note: --output-format json produces a summary object (no messages array).
        # Token totals must be summed from modelUsage (per-model breakdown) to
        # include subagent work. The top-level .usage only covers the outer session.
        output_file="$condition_dir/output.json"
        if [ -f "$output_file" ]; then
            turns=$(jq -r '.num_turns // 0' "$output_file" 2>/dev/null || echo "0")
            cost_usd=$(jq -r '.total_cost_usd // 0' "$output_file" 2>/dev/null || echo "0")

            # Sum tokens across all models (includes subagent usage)
            input_tokens=$(jq -r '[.modelUsage[]?.inputTokens // 0] | add // 0' "$output_file" 2>/dev/null || echo "0")
            output_tokens=$(jq -r '[.modelUsage[]?.outputTokens // 0] | add // 0' "$output_file" 2>/dev/null || echo "0")

            # Haiku output tokens = subagent activity (wiki-explorer/reflector run on haiku).
            # Control baseline is ~200-600 tokens of Claude Code internal overhead.
            subagent_out=$(jq -r '.modelUsage["claude-haiku-4-5-20251001"].outputTokens // 0' "$output_file" 2>/dev/null || echo "0")
        else
            turns=0; cost_usd=0; input_tokens=0; output_tokens=0; subagent_out=0
        fi

        # Count lines of code in workspace
        workspace="$condition_dir/workspace"
        if [ -d "$workspace" ]; then
            lines_of_code=$(find "$workspace" -name "*.py" -not -path "*/data/*" -not -path "*/.claude/*" -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/node_modules/*" -exec cat {} + 2>/dev/null | wc -l || echo "0")
        else
            lines_of_code=0
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$problem" "$condition" "$duration" "$turns" "$cost_usd" \
            "$subagent_out" "$lines_of_code" "$input_tokens" "$output_tokens" \
            >> "$STATS_FILE"
    done
done

echo ""
echo "Stats written to: $STATS_FILE"
echo ""
echo "=== Summary ==="
column -t -s$'\t' "$STATS_FILE"
