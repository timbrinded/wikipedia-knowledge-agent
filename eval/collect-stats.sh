#!/usr/bin/env bash
set -euo pipefail

# Collect quantitative metrics from experiment results.
#
# For each problem × condition, extracts:
#   - Duration (total, research phase, code phase)
#   - Number of turns (code phase)
#   - Total cost (total, research phase, code phase)
#   - Research output tokens and articles found
#   - Lines of code produced
#   - Token usage (input/output, summed across all models)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
STATS_FILE="$RESULTS_DIR/stats.tsv"

echo "=== Collecting experiment statistics ==="

# Header
printf "problem\tcondition\ttotal_duration_s\tresearch_duration_s\tcode_duration_s\ttotal_cost_usd\tresearch_cost_usd\tcode_cost_usd\tresearch_output_tokens\tresearch_articles_found\tretrieval_turns\tretrieval_retry\tsynthesis_duration_s\tturns\tlines_of_code\tinput_tokens\toutput_tokens\n" > "$STATS_FILE"

for problem_dir in "$RESULTS_DIR"/*/; do
    problem=$(basename "$problem_dir")
    [ -d "$problem_dir" ] || continue
    # Skip non-problem dirs
    [[ "$problem" == "stats.tsv" || "$problem" == "evaluations" || "$problem" == "visualize.ipynb" ]] && continue

    for condition_dir in "$problem_dir"/*/; do
        condition=$(basename "$condition_dir")
        [ -d "$condition_dir" ] || continue
        [ -f "$condition_dir/done" ] || continue

        # Duration from meta.json (supports both old and new format)
        total_duration=$(jq -r '.total_duration_seconds // .duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")
        research_duration=$(jq -r '.research_duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")
        code_duration=$(jq -r '.code_duration_seconds // .duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")

        # --- Retrieval stage metrics ---
        retrieval_file="$condition_dir/retrieval.json"
        retrieval_turns=0
        retrieval_retry=0
        retrieval_cost_usd=0
        synthesis_duration=0
        if [ -f "$retrieval_file" ]; then
            retrieval_turns=$(jq -r '.num_turns // 0' "$retrieval_file" 2>/dev/null || echo "0")
            retrieval_cost_usd=$(jq -r '.total_cost_usd // 0' "$retrieval_file" 2>/dev/null || echo "0")
        fi
        if [ -f "$condition_dir/retrieval_retry.json" ]; then
            retrieval_retry=1
            # Add retry cost
            retry_cost=$(jq -r '.total_cost_usd // 0' "$condition_dir/retrieval_retry.json" 2>/dev/null || echo "0")
            retrieval_cost_usd=$(awk "BEGIN {printf \"%.6f\", $retrieval_cost_usd + $retry_cost}" 2>/dev/null || echo "$retrieval_cost_usd")
        fi
        synthesis_duration=$(jq -r '.synthesis_duration_seconds // 0' "$condition_dir/meta.json" 2>/dev/null || echo "0")

        # --- Research phase metrics (from research.json = synthesis output) ---
        research_file="$condition_dir/research.json"
        synthesis_cost_usd=0
        research_output_tokens=0
        research_articles_found=0
        if [ -f "$research_file" ]; then
            synthesis_cost_usd=$(jq -r '.total_cost_usd // 0' "$research_file" 2>/dev/null || echo "0")
            research_output_tokens=$(jq -r '[.modelUsage[]?.outputTokens // 0] | add // 0' "$research_file" 2>/dev/null || echo "0")

            # Count unique article paths mentioned in research output
            research_result=$(jq -r '.result // ""' "$research_file" 2>/dev/null || echo "")
            if [ -n "$research_result" ]; then
                research_articles_found=$(echo "$research_result" | grep -oP 'data/articles/[^\s"]+' | sort -u | wc -l || echo "0")
            fi
        fi

        # Research cost = retrieval + synthesis
        research_cost_usd=$(awk "BEGIN {printf \"%.6f\", $retrieval_cost_usd + $synthesis_cost_usd}" 2>/dev/null || echo "$synthesis_cost_usd")

        # --- Code phase metrics (from output.json) ---
        output_file="$condition_dir/output.json"
        code_cost_usd=0
        turns=0
        input_tokens=0
        output_tokens=0
        if [ -f "$output_file" ]; then
            turns=$(jq -r '.num_turns // 0' "$output_file" 2>/dev/null || echo "0")
            code_cost_usd=$(jq -r '.total_cost_usd // 0' "$output_file" 2>/dev/null || echo "0")

            # Sum tokens across all models (includes subagent usage)
            input_tokens=$(jq -r '[.modelUsage[]?.inputTokens // 0] | add // 0' "$output_file" 2>/dev/null || echo "0")
            output_tokens=$(jq -r '[.modelUsage[]?.outputTokens // 0] | add // 0' "$output_file" 2>/dev/null || echo "0")
        fi

        # Total cost = research + code
        total_cost_usd=$(awk "BEGIN {printf \"%.6f\", $research_cost_usd + $code_cost_usd}" 2>/dev/null || echo "$code_cost_usd")

        # Count lines of code in workspace
        workspace="$condition_dir/workspace"
        if [ -d "$workspace" ]; then
            lines_of_code=$(find "$workspace" -name "*.py" -not -name "types.py" -not -path "*/data/*" -not -path "*/.claude/*" -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/node_modules/*" -exec cat {} + 2>/dev/null | wc -l || echo "0")
        else
            lines_of_code=0
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$problem" "$condition" "$total_duration" "$research_duration" "$code_duration" \
            "$total_cost_usd" "$research_cost_usd" "$code_cost_usd" \
            "$research_output_tokens" "$research_articles_found" \
            "$retrieval_turns" "$retrieval_retry" "$synthesis_duration" \
            "$turns" "$lines_of_code" "$input_tokens" "$output_tokens" \
            >> "$STATS_FILE"
    done
done

echo ""
echo "Stats written to: $STATS_FILE"
echo ""
echo "=== Summary ==="
column -t -s$'\t' "$STATS_FILE"
