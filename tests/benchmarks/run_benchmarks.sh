#!/usr/bin/env bash
set -euo pipefail

# Run benchmarks for all problem × condition combinations.
#
# Iterates over results/{problem}/{condition}/workspace/ directories,
# runs the matching benchmark script, and writes JSON results to
# results/benchmarks/{problem}/{condition}.json.
#
# Usage:
#   ./tests/benchmarks/run_benchmarks.sh
#   PROBLEMS="01-load-balancer" CONDITIONS="control explicit" ./tests/benchmarks/run_benchmarks.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
RESULTS_DIR="$PROJECT_DIR/results"
BENCHMARKS_DIR="$SCRIPT_DIR"
CONTRACTS_DIR="$SCRIPT_DIR/../contracts"
BENCHMARK_RESULTS_DIR="$RESULTS_DIR/benchmarks"
SEED="${SEED:-42}"

# Map problem slug to benchmark file
# "01-load-balancer" -> "01_load_balancer.py"
benchmark_file_for() {
    local problem_name="$1"
    local bench_name
    bench_name=$(echo "$problem_name" | tr '-' '_')
    echo "$BENCHMARKS_DIR/${bench_name}.py"
}

# Discover problems and conditions from results directory
if [ ! -d "$RESULTS_DIR" ]; then
    echo "ERROR: No results directory at $RESULTS_DIR"
    echo "Run experiments first with ./tests/run-experiment.sh"
    exit 1
fi

# Allow filtering via environment
PROBLEMS="${PROBLEMS:-$(ls -d "$RESULTS_DIR"/*/ 2>/dev/null | xargs -n1 basename | grep -v benchmarks | sort)}"
CONDITIONS="${CONDITIONS:-}"

echo "=== Load Balancer Benchmark Runner ==="
echo "Seed: $SEED"
echo ""

total=0
success=0
skipped=0
failed=0

for problem_name in $PROBLEMS; do
    problem_dir="$RESULTS_DIR/$problem_name"
    [ -d "$problem_dir" ] || continue

    bench_file=$(benchmark_file_for "$problem_name")
    if [ ! -f "$bench_file" ]; then
        echo "--- $problem_name: no benchmark found ($(basename "$bench_file")), skipping ---"
        continue
    fi

    echo "--- Problem: $problem_name ---"

    # Discover conditions (or use filter)
    if [ -n "$CONDITIONS" ]; then
        conds="$CONDITIONS"
    else
        conds=$(ls -d "$problem_dir"/*/ 2>/dev/null | xargs -n1 basename | sort)
    fi

    for condition in $conds; do
        workspace="$problem_dir/$condition/workspace"
        if [ ! -d "$workspace" ]; then
            echo "  SKIP $condition (no workspace)"
            skipped=$((skipped + 1))
            continue
        fi

        # Only benchmark completed experiments
        if [ ! -f "$problem_dir/$condition/done" ]; then
            echo "  SKIP $condition (experiment not finished)"
            skipped=$((skipped + 1))
            continue
        fi

        # Check if implementation exists (not just the contract types.py)
        if [ ! -f "$workspace/load_balancer/__init__.py" ] && [ ! -f "$workspace/load_balancer.py" ]; then
            echo "  SKIP $condition (no load_balancer implementation)"
            skipped=$((skipped + 1))
            continue
        fi

        outdir="$BENCHMARK_RESULTS_DIR/$problem_name"
        outfile="$outdir/${condition}.json"
        mkdir -p "$outdir"

        total=$((total + 1))
        echo -n "  BENCH $condition ... "

        # Run benchmark as subprocess with clean import environment
        if python3 "$bench_file" \
            --workspace "$workspace" \
            --output "$outfile" \
            --seed "$SEED" \
            > "$outdir/${condition}.log" 2>&1; then

            # Extract aggregate score from JSON
            score=$(python3 -c "import json; print(json.load(open('$outfile'))['aggregate_score'])" 2>/dev/null || echo "?")
            echo "score=$score"
            success=$((success + 1))
        else
            echo "FAILED (see $outdir/${condition}.log)"
            failed=$((failed + 1))
        fi
    done
    echo ""
done

echo "=== Benchmark Summary ==="
echo "Total: $total | Success: $success | Failed: $failed | Skipped: $skipped"

if [ $success -gt 0 ]; then
    echo ""
    echo "Run ./tests/benchmarks/report.py to generate comparison table."
fi
