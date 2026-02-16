#!/usr/bin/env bash
set -euo pipefail

# LLM-as-Judge evaluation.
#
# For each problem, presents the control and explicit/subtle outputs
# (blinded) to a separate LLM and asks it to evaluate.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
EVAL_DIR="$RESULTS_DIR/evaluations"

CLAUDE_CMD="${CLAUDE_CMD:-claude}"

JUDGE_PROMPT='You are evaluating two solutions to the same coding problem. You do not know which solution had access to additional resources.

## Problem
%PROBLEM%

## Solution A
%SOLUTION_A%

## Solution B
%SOLUTION_B%

## Evaluation Criteria

Score each solution 1-10 on:
1. **Correctness** — Does it work? Does it handle edge cases?
2. **Design quality** — Is the architecture clean, extensible, well-structured?
3. **Creativity** — Does it show novel approaches, interesting patterns, or lateral thinking?
4. **Robustness** — How well does it handle failure cases, edge cases, scaling?
5. **Cross-domain insight** — Does it draw on knowledge from outside pure programming? (biology, physics, social science, etc.)

## Output Format (strict JSON)

{
  "solution_a": {
    "correctness": N,
    "design": N,
    "creativity": N,
    "robustness": N,
    "cross_domain": N,
    "total": N,
    "notes": "brief explanation"
  },
  "solution_b": {
    "correctness": N,
    "design": N,
    "creativity": N,
    "robustness": N,
    "cross_domain": N,
    "total": N,
    "notes": "brief explanation"
  },
  "preferred": "a" or "b" or "tie",
  "reasoning": "why one is better, focusing on any qualitative differences in approach"
}'

echo "=== LLM-as-Judge Evaluation ==="
mkdir -p "$EVAL_DIR"

for problem_dir in "$RESULTS_DIR"/*/; do
    problem=$(basename "$problem_dir")
    [ -d "$problem_dir" ] || continue
    [[ "$problem" == "evaluations" || "$problem" == "stats.tsv" ]] && continue

    problem_file="$PROJECT_DIR/tests/problems/${problem}.md"
    [ -f "$problem_file" ] || continue

    echo ""
    echo "--- Evaluating: $problem ---"

    problem_text=$(cat "$problem_file")

    # Get control solution
    control_workspace="$problem_dir/control/workspace"
    if [ ! -d "$control_workspace" ]; then
        echo "  SKIP (no control solution)"
        continue
    fi
    control_code=$(find "$control_workspace" -name "*.py" -not -path "*/data/*" -not -path "*/.claude/*" -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null || echo "(no code)")

    # Compare control against each wiki condition
    for condition in explicit subtle; do
        wiki_workspace="$problem_dir/$condition/workspace"
        [ -d "$wiki_workspace" ] || continue

        wiki_code=$(find "$wiki_workspace" -name "*.py" -not -path "*/data/*" -not -path "*/.claude/*" -exec echo "--- {} ---" \; -exec cat {} \; 2>/dev/null || echo "(no code)")

        # Randomise which is A/B to avoid position bias
        coin=$((RANDOM % 2))
        if [ $coin -eq 0 ]; then
            solution_a="$control_code"
            solution_b="$wiki_code"
            mapping="a=control,b=$condition"
        else
            solution_a="$wiki_code"
            solution_b="$control_code"
            mapping="a=$condition,b=control"
        fi

        # Build prompt
        prompt="${JUDGE_PROMPT//%PROBLEM%/$problem_text}"
        prompt="${prompt//%SOLUTION_A%/$solution_a}"
        prompt="${prompt//%SOLUTION_B%/$solution_b}"

        eval_file="$EVAL_DIR/${problem}_${condition}.json"

        echo "  JUDGE $problem: control vs $condition"
        $CLAUDE_CMD -p "$prompt" --output-format json > "$eval_file" 2>/dev/null || true

        # Record the blinding mapping
        echo "{\"mapping\": \"$mapping\"}" > "$EVAL_DIR/${problem}_${condition}_mapping.json"

        echo "  DONE  → $eval_file"
    done
done

echo ""
echo "=== Evaluation complete ==="
echo "Results in: $EVAL_DIR"
