#!/usr/bin/env python3
"""
Benchmark Report Generator.

Aggregates per-condition JSON results from results/benchmarks/{problem}/{condition}.json
into a comparison TSV and prints a ranked summary table.

Usage:
    python3 report.py [--results-dir ../../results/benchmarks] [--output report.tsv]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_results(results_dir: Path) -> dict[str, dict[str, dict]]:
    """
    Load all benchmark results.

    Returns:
        {problem: {condition: result_dict}}
    """
    data: dict[str, dict[str, dict]] = {}

    for problem_dir in sorted(results_dir.iterdir()):
        if not problem_dir.is_dir():
            continue
        problem = problem_dir.name
        data[problem] = {}

        for json_file in sorted(problem_dir.glob("*.json")):
            condition = json_file.stem
            try:
                result = json.loads(json_file.read_text())
                data[problem][condition] = result
            except (json.JSONDecodeError, OSError) as e:
                print(f"WARNING: Failed to read {json_file}: {e}", file=sys.stderr)
                data[problem][condition] = {"aggregate_score": 0.0, "error": str(e)}

    return data


def print_comparison_table(data: dict[str, dict[str, dict]]) -> None:
    """Print a formatted comparison table to stdout."""
    for problem, conditions in data.items():
        if not conditions:
            continue

        print(f"\n{'=' * 70}")
        print(f"  Problem: {problem}")
        print(f"{'=' * 70}")

        # Sort by aggregate score descending
        ranked = sorted(conditions.items(), key=lambda x: x[1].get("aggregate_score", 0), reverse=True)

        # Header
        print(f"\n  {'Rank':<6}{'Condition':<16}{'Score':>8}  Scenario Breakdown")
        print(f"  {'─' * 60}")

        for rank, (condition, result) in enumerate(ranked, 1):
            score = result.get("aggregate_score", 0.0)
            error = result.get("error", "")

            if error and not result.get("scenarios"):
                print(f"  {rank:<6}{condition:<16}{score:>7.1f}  IMPORT ERROR")
                continue

            # Scenario breakdown
            scenarios = result.get("scenarios", [])
            breakdown = "  ".join(
                f"{s['name'][:4]}={s['score']:.2f}" for s in scenarios
            )

            # Medal for top 3
            medal = {1: " 🥇", 2: " 🥈", 3: " 🥉"}.get(rank, "")
            print(f"  {rank:<6}{condition:<16}{score:>7.1f}  {breakdown}{medal}")

        print()


def write_tsv(data: dict[str, dict[str, dict]], output_path: Path) -> None:
    """Write a TSV file with all results for further analysis."""
    # Collect all scenario names from first result
    scenario_names: list[str] = []
    for conditions in data.values():
        for result in conditions.values():
            for s in result.get("scenarios", []):
                if s["name"] not in scenario_names:
                    scenario_names.append(s["name"])
            if scenario_names:
                break
        if scenario_names:
            break

    headers = ["problem", "condition", "aggregate_score", "rank"] + [f"s_{name}" for name in scenario_names]

    lines = ["\t".join(headers)]

    for problem, conditions in data.items():
        ranked = sorted(conditions.items(), key=lambda x: x[1].get("aggregate_score", 0), reverse=True)

        for rank, (condition, result) in enumerate(ranked, 1):
            score = result.get("aggregate_score", 0.0)
            scenario_scores = {s["name"]: s["score"] for s in result.get("scenarios", [])}

            row = [
                problem,
                condition,
                f"{score:.2f}",
                str(rank),
            ]
            for sname in scenario_names:
                row.append(f"{scenario_scores.get(sname, 0.0):.4f}")

            lines.append("\t".join(row))

    output_path.write_text("\n".join(lines) + "\n")
    print(f"\nTSV written to: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark Report Generator")
    parser.add_argument(
        "--results-dir",
        default=None,
        help="Path to benchmarks results directory (default: auto-detect)",
    )
    parser.add_argument("--output", default=None, help="Path to write TSV output")
    args = parser.parse_args()

    # Auto-detect results directory
    if args.results_dir:
        results_dir = Path(args.results_dir).resolve()
    else:
        # Try relative to script location
        results_dir = Path(__file__).resolve().parent.parent.parent / "results" / "benchmarks"

    if not results_dir.exists():
        print(f"ERROR: Results directory not found: {results_dir}", file=sys.stderr)
        print("Run benchmarks first with ./tests/benchmarks/run_benchmarks.sh", file=sys.stderr)
        sys.exit(1)

    data = load_results(results_dir)

    if not data:
        print("No benchmark results found.", file=sys.stderr)
        sys.exit(1)

    print_comparison_table(data)

    # Write TSV
    if args.output:
        output_path = Path(args.output).resolve()
    else:
        output_path = results_dir / "report.tsv"

    write_tsv(data, output_path)


if __name__ == "__main__":
    main()
