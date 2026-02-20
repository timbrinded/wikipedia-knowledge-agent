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
AGENTS_DIR="$PROJECT_DIR/agents"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"

# Configurable
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PROBLEMS="${PROBLEMS:-$(ls "$PROBLEMS_DIR"/*.md | sort)}"
CONDITIONS="${CONDITIONS:-control explicit subtle reflective flaneur consilience biomimetic contrarian}"

# Build extra Claude CLI flags for a given condition (phase 2 — coding)
claude_extra_args() {
    local condition="$1"
    local workdir="$2"
    local args=""
    if [ "$condition" != "control" ]; then
        args="--plugin-dir $PLUGIN_DIR"
    fi
    echo "$args"
}

# Map condition → agent file
agent_file_for_condition() {
    local condition="$1"
    case "$condition" in
        explicit)    echo "$AGENTS_DIR/wiki-explorer.md" ;;
        reflective)  echo "$AGENTS_DIR/wiki-reflector.md" ;;
        flaneur)     echo "$AGENTS_DIR/wiki-flaneur.md" ;;
        consilience) echo "$AGENTS_DIR/wiki-consilience.md" ;;
        biomimetic)  echo "$AGENTS_DIR/wiki-biomimetic.md" ;;
        contrarian)  echo "$AGENTS_DIR/wiki-contrarian.md" ;;
        *)           echo "" ;;
    esac
}

# Map condition → research instruction
research_instruction_for_condition() {
    local condition="$1"
    case "$condition" in
        explicit)    echo "Research cross-domain analogues for this problem." ;;
        reflective)  echo "Find historical precedent and proportionality checks for this problem." ;;
        flaneur)     echo "Take a random walk through Wikipedia, then reflect on connections to this problem." ;;
        consilience) echo "Find convergent patterns across 3+ independent domains for this problem." ;;
        biomimetic)  echo "Find biological and ecological analogues for this problem." ;;
        contrarian)  echo "Stress-test the obvious approach to this problem. Find evidence against the default." ;;
        *)           echo "" ;;
    esac
}

# Extract system prompt from agent .md file (everything after YAML frontmatter)
extract_agent_system_prompt() {
    local agent_file="$1"
    # Skip YAML frontmatter: drop everything from first --- to second ---
    sed -n '/^---$/,/^---$/!p' "$agent_file"
}

# Conditions that get a research phase (have wiki agents)
condition_has_research() {
    local condition="$1"
    case "$condition" in
        explicit|reflective|flaneur|consilience|biomimetic|contrarian) return 0 ;;
        *) return 1 ;;
    esac
}

# Run the research phase for a wiki condition.
# Produces $outdir/research.json with the raw output.
# Returns the research text via stdout (caller captures it).
run_research_phase() {
    local problem_spec="$1"
    local condition="$2"
    local outdir="$3"
    local workdir="$4"

    local agent_file
    agent_file=$(agent_file_for_condition "$condition")
    if [ -z "$agent_file" ] || [ ! -f "$agent_file" ]; then
        echo "ERROR: No agent file for condition '$condition'" >&2
        return 1
    fi

    local agent_system_prompt
    agent_system_prompt=$(extract_agent_system_prompt "$agent_file")

    local research_instruction
    research_instruction=$(research_instruction_for_condition "$condition")

    local research_prompt="You are running in non-interactive mode. Do NOT use AskUserQuestion. Do NOT enter plan mode. Do NOT write any code.

You are a Wikipedia research agent. Your ONLY job is to search the local Wikipedia corpus and produce structured research findings.

${agent_system_prompt}

---

PROBLEM TO RESEARCH:
${problem_spec}

---

INSTRUCTIONS:
1. ${research_instruction}
2. Search the Wikipedia corpus in data/articles/ using grep patterns and file reads
3. Read relevant articles deeply
4. Produce structured findings following your Output Shape format
5. Do NOT write any implementation code — only research findings"

    echo "  RESEARCH $condition — starting research phase..." >&2
    local research_start
    research_start=$(date +%s)

    # Run research agent standalone — no --plugin-dir (just Bash/Read/Glob access)
    (cd "$workdir" && \
    CLAUDECODE= $CLAUDE_CMD -p "$research_prompt" \
        --dangerously-skip-permissions \
        --output-format json \
        > "$outdir/research.json" \
        2> "$outdir/research_stderr.log" \
        || true)

    local research_end
    research_end=$(date +%s)
    local research_duration=$(( research_end - research_start ))

    echo "  RESEARCH $condition — done (${research_duration}s)" >&2

    # Extract the result text from the JSON output
    local research_text
    research_text=$(jq -r '.result // ""' "$outdir/research.json" 2>/dev/null || echo "")

    # Write duration to a file so the caller can read it
    # (command substitution runs in a subshell, so env vars don't propagate)
    echo "$research_duration" > "$outdir/research_duration"

    echo "$research_text"
}

# Universal preamble — ensures the agent writes code directly in non-interactive mode
PREAMBLE_UNIVERSAL="You are running in non-interactive mode. Implement the solution fully by yourself. Do NOT use AskUserQuestion or ask for user input — write all code directly. Do NOT enter plan mode. Just implement the solution and write the files.

"

# Preambles for each condition
# Search instructions now live in each agent's .md file ("Scrubbing the Corpus" block)
PREAMBLE_CONTROL=""
PREAMBLE_EXPLICIT="Wikipedia research has already been conducted for you (see \"Wikipedia Research Findings\" above).
Use these findings to inform your implementation. Do not repeat the research. Reference specific concepts or analogues in code comments where they influenced your approach.

"
PREAMBLE_SUBTLE=""

PREAMBLE_REFLECTIVE="You are a historically-informed engineer. You don't just write correct code — you think about regret. Before committing to an approach, you consider: what has been tried before? What failed? Is this complexity proportionate to the problem?

Wikipedia research has already been conducted for you (see \"Wikipedia Research Findings\" above).
Use these findings — historical precedent, cautionary tales, proportionality checks — to inform your implementation. Do not repeat the research.

"

# --- Wave 2 conditions ---
# (Research is now done in a separate phase — preambles just tell the coder to USE the findings)

PREAMBLE_FLANEUR="A wiki-flaneur agent has already taken a random walk through Wikipedia for you (see \"Wikipedia Research Findings\" above).
The flaneur wandered without agenda, followed curiosity, and reflected on what might connect to your problem. Let the texture settle. Let whatever resonated from the walk influence your design, even if the connection is loose.
Do not repeat the research.

"

PREAMBLE_CONSILIENCE="Wikipedia research has already been conducted for you (see \"Wikipedia Research Findings\" above).
A wiki-consilience agent searched for convergent evidence — the same structural pattern appearing independently across 3+ unrelated domains. If it found strong consilience, treat that as strong evidence the pattern is fundamental — build on it. If consilience is weak, proceed with standard engineering.
Do not repeat the research.

"

PREAMBLE_BIOMIMETIC="Wikipedia research has already been conducted for you (see \"Wikipedia Research Findings\" above).
A wiki-biomimetic agent searched biology and ecology — evolution, neuroscience, immunology, ethology, botany, mycology — for how nature solves the same structural problem. If it found a biological mechanism that translates well to code, implement it as an actual algorithm or architecture derived from the mechanism, not just a metaphor. If the biological lens doesn't improve on standard approaches, proceed with standard engineering.
Do not repeat the research.

"

PREAMBLE_CONTRARIAN="Wikipedia research has already been conducted for you (see \"Wikipedia Research Findings\" above).
A wiki-contrarian agent stress-tested the obvious approach — searching for historical failures, known limitations, documented anti-patterns, and cases where the standard solution lost. If it found compelling evidence against the default, reconsider your approach. If the default survived scrutiny, proceed with higher confidence.
Do not repeat the research.

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

    # Set up workspace — symlink Wikipedia data for non-control conditions
    if [ "$condition" != "control" ]; then
        ln -sfn "$DATA_DIR" "$workdir/data"
    fi

    # --- Phase 1: Research (for wiki conditions only) ---
    local research_text=""
    local research_duration=0
    if condition_has_research "$condition"; then
        research_text=$(run_research_phase "$prompt" "$condition" "$outdir" "$workdir")
        research_duration=$(cat "$outdir/research_duration" 2>/dev/null || echo "0")
    fi

    # --- Phase 2: Coding ---
    # Build the full prompt based on condition
    local research_section=""
    if [ -n "$research_text" ]; then
        research_section="
## Wikipedia Research Findings
The following research was conducted by the ${condition} research agent before you began:
---
${research_text}
---
Use these findings to inform your design. Reference specific concepts where they influenced your approach.

"
    fi

    local full_prompt
    case "$condition" in
        control)
            full_prompt="${PREAMBLE_UNIVERSAL}${prompt}"
            ;;
        explicit)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_EXPLICIT}${prompt}"
            ;;
        subtle)
            # For subtle: we install the skill but don't mention it in the prompt.
            # The agent can discover the tools via SKILL.md in the workspace.
            full_prompt="${PREAMBLE_UNIVERSAL}${prompt}"
            ;;
        reflective)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_REFLECTIVE}${prompt}"
            ;;
        flaneur)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_FLANEUR}${prompt}"
            ;;
        consilience)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_CONSILIENCE}${prompt}"
            ;;
        biomimetic)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_BIOMIMETIC}${prompt}"
            ;;
        contrarian)
            full_prompt="${PREAMBLE_UNIVERSAL}${research_section}${PREAMBLE_CONTRARIAN}${prompt}"
            ;;
        *)
            echo "ERROR: Unknown condition '$condition'" >&2
            return 1
            ;;
    esac

    # Build extra CLI flags (--plugin-dir for non-control)
    local extra_args
    extra_args=$(claude_extra_args "$condition" "$workdir")

    echo "  RUN  $problem_name/$condition (coding phase)"
    local code_start
    code_start=$(date +%s)

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

    local code_end
    code_end=$(date +%s)
    local code_duration=$(( code_end - code_start ))
    local total_duration=$(( research_duration + code_duration ))

    # Record metadata
    cat > "$outdir/meta.json" << METAEOF
{
    "problem": "$problem_name",
    "condition": "$condition",
    "research_duration_seconds": $research_duration,
    "code_duration_seconds": $code_duration,
    "total_duration_seconds": $total_duration,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "claude_cmd": "$CLAUDE_CMD"
}
METAEOF

    touch "$outdir/done"
    echo "  DONE $problem_name/$condition (research: ${research_duration}s, code: ${code_duration}s, total: ${total_duration}s)"
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
