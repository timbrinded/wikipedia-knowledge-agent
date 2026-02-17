#!/usr/bin/env bash
set -euo pipefail

# LLM-as-Judge evaluation.
#
# For each problem, presents the control and explicit/subtle outputs
# (blinded) to a separate LLM and asks it to evaluate.
# Commentary is excluded — judge evaluates CODE ONLY.
# Comments are stripped from code to prevent narrative inflation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$PROJECT_DIR/results"
EVAL_DIR="$RESULTS_DIR/evaluations"

CLAUDE_CMD="${CLAUDE_CMD:-claude}"

JUDGE_PROMPT='You are evaluating two solutions to the same coding problem. You do not know which solution had access to additional resources. You are evaluating CODE ONLY — no commentary is provided.

Score each solution 1-10. BE CRITICAL. Most competent solutions score 5-7. Reserve 8+ for genuinely exceptional work. Reserve 1-3 for broken or fundamentally flawed code.

CALIBRATION: If both solutions use the same core algorithm and produce equivalent behavior, they MUST receive the same score on correctness, design, robustness, and algorithmic novelty — regardless of differences in comments, variable names, test count, or prose. Extra tests are a minor bonus to robustness (+1 max), not algorithmic novelty.

## Problem
%PROBLEM%

## Solution A — Code
%SOLUTION_A_CODE%

## Solution B — Code
%SOLUTION_B_CODE%

## Evaluation Criteria

1. **Correctness** (weight: 3x) — Does it produce correct results? Does it handle boundary conditions? Run through the logic mentally for edge cases. Deduct for bugs, even subtle ones.

2. **Design quality** (weight: 2x) — Is the architecture clean and well-structured? Are abstractions appropriate (not over-engineered, not under-engineered)? Would this be maintainable?

3. **Robustness** (weight: 2x) — Does it handle failures, invalid input, and resource limits? Does it degrade gracefully under stress? Only count mechanisms visible in the code, not aspirational comments.

4. **Algorithmic novelty** (weight: 2x) — Does the solution use a genuinely different or superior algorithm, data structure, or design pattern compared to the obvious textbook approach? "Different" alone is not novel — it must be *better* or *more interesting* in a way that affects behavior.

5. **Cross-domain structural insight** (weight: 1x) — Does the code'\''s *actual behavior* (not comments, not variable names) embody a pattern drawn from outside software engineering? Example: a load balancer that implements biological quorum sensing as its consensus mechanism scores high. A load balancer with a comment saying "inspired by quorum sensing" but using standard round-robin scores 1. The insight must be *structural*, not *decorative*.

6. **Proportionality** (weight: 1x) — Is the solution'\''s complexity proportionate to the problem? Deduct for over-engineering (complex architecture for a simple problem — e.g., microservice patterns for a single-file utility) or under-engineering (naive approach to a problem with known pitfalls — e.g., no error handling for network I/O). The best solutions use exactly as much complexity as the problem demands — no more, no less.

## Output Format (strict JSON)

{
  "solution_a": {
    "correctness": N,
    "design": N,
    "robustness": N,
    "algorithmic_novelty": N,
    "cross_domain": N,
    "proportionality": N,
    "total": 3*correctness + 2*design + 2*robustness + 2*algorithmic_novelty + 1*cross_domain + 1*proportionality,
    "notes": "brief explanation"
  },
  "solution_b": {
    "correctness": N,
    "design": N,
    "robustness": N,
    "algorithmic_novelty": N,
    "cross_domain": N,
    "proportionality": N,
    "total": 3*correctness + 2*design + 2*robustness + 2*algorithmic_novelty + 1*cross_domain + 1*proportionality,
    "notes": "brief explanation"
  },
  "preferred": "a" or "b" or "tie",
  "reasoning": "why one is better, focusing on any qualitative differences in approach"
}'

# Extract .py code files from workspace, stripping comments and blank lines.
# Uses Python's tokenizer to correctly distinguish comments from # in strings.
extract_code() {
    local workspace="$1"
    local code=""
    if [ -d "$workspace" ]; then
        code=$(find "$workspace" -name "*.py" -not -path "*/data/*" -not -path "*/.claude/*" -not -path "*/.venv/*" -not -path "*/venv/*" -not -path "*/node_modules/*" \
            -exec cat {} + 2>/dev/null \
            | python3 "$SCRIPT_DIR/strip_comments.py")
    fi
    [ -z "$code" ] && code="(no code files produced)"
    echo "$code"
}

echo "=== LLM-as-Judge Evaluation ==="
mkdir -p "$EVAL_DIR"

for problem_dir in "$RESULTS_DIR"/*/; do
    problem=$(basename "$problem_dir")
    [ -d "$problem_dir" ] || continue
    [[ "$problem" == "evaluations" || "$problem" == "stats.tsv" || "$problem" == "visualize.ipynb" ]] && continue

    problem_file="$PROJECT_DIR/tests/problems/${problem}.md"
    [ -f "$problem_file" ] || continue

    echo ""
    echo "--- Evaluating: $problem ---"

    problem_text=$(cat "$problem_file")

    # Get control solution
    if [ ! -f "$problem_dir/control/output.json" ]; then
        echo "  SKIP (no control solution)"
        continue
    fi
    control_code=$(extract_code "$problem_dir/control/workspace")

    # Compare control against each wiki condition
    for condition_dir in "$problem_dir"/*/; do
        condition=$(basename "$condition_dir")
        [ "$condition" = "control" ] && continue
        [ -f "$problem_dir/$condition/output.json" ] || continue

        wiki_code=$(extract_code "$problem_dir/$condition/workspace")

        # Randomise which is A/B to avoid position bias
        coin=$((RANDOM % 2))
        if [ $coin -eq 0 ]; then
            sol_a_code="$control_code"
            sol_b_code="$wiki_code"
            mapping="a=control,b=$condition"
        else
            sol_a_code="$wiki_code"
            sol_b_code="$control_code"
            mapping="a=$condition,b=control"
        fi

        # Build prompt (code only, no commentary)
        prompt="${JUDGE_PROMPT//%PROBLEM%/$problem_text}"
        prompt="${prompt//%SOLUTION_A_CODE%/$sol_a_code}"
        prompt="${prompt//%SOLUTION_B_CODE%/$sol_b_code}"

        eval_file="$EVAL_DIR/${problem}_${condition}.json"

        # Skip if already evaluated (non-empty file). Set FORCE=1 to re-evaluate.
        if [ "${FORCE:-}" != "1" ] && [ -f "$eval_file" ] && [ -s "$eval_file" ]; then
            echo "  SKIP $problem/$condition (already evaluated)"
            continue
        fi

        echo "  JUDGE $problem: control vs $condition"
        CLAUDECODE= $CLAUDE_CMD -p "$prompt" --output-format json > "$eval_file" 2>/dev/null || true

        # Record the blinding mapping
        echo "{\"mapping\": \"$mapping\"}" > "$EVAL_DIR/${problem}_${condition}_mapping.json"

        echo "  DONE  -> $eval_file"
    done
done

echo ""
echo "=== Evaluation complete ==="
echo "Results in: $EVAL_DIR"
