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

# Map condition → retrieval search strategy (derived from agent .md "How to Think" sections)
retrieval_search_strategy() {
    local condition="$1"
    case "$condition" in
        explicit)    echo "Abstract the problem. Search for structural patterns across domains: ecology, physics, economics, history. Follow surprising connections." ;;
        reflective)  echo "Search for historical precedent: prior attempts, failures, evolution of approaches. Search for proportionality comparisons." ;;
        flaneur)     echo "Pick random articles with shuf. Follow curiosity, not relevance. Read 3-5 full articles." ;;
        consilience) echo "Search for the abstract pattern across 5+ independent domains. Look for convergent solutions." ;;
        biomimetic)  echo "Reframe the problem biologically. Search ONLY in ecology, evolution, neuroscience, immunology, ethology, botany, mycology." ;;
        contrarian)  echo "Name the obvious approach. Search for its failures, limitations, documented anti-patterns." ;;
        *)           echo "" ;;
    esac
}

# Derive a seed search term from the problem filename
seed_term_from_problem_name() {
    local problem_name="$1"
    # Strip leading number prefix (e.g., "01-") and replace hyphens with spaces
    echo "$problem_name" | sed 's/^[0-9]*-//' | tr '-' ' '
}

# Map (condition, problem_name) → mandatory first command for retrieval stage
retrieval_first_command() {
    local condition="$1"
    local problem_name="$2"
    local seed_term
    seed_term=$(seed_term_from_problem_name "$problem_name")

    case "$condition" in
        flaneur) echo "shuf -n 1 data/index/titles.txt" ;;
        *)       echo "rg -l -i \"${seed_term}\" data/articles/ | head -30" ;;
    esac
}

# Verify that the retrieval stage actually used tools (num_turns > 1, article refs >= 2)
verify_retrieval() {
    local json_file="$1"
    local num_turns
    num_turns=$(jq -r '.num_turns // 0' "$json_file" 2>/dev/null || echo "0")

    if [ "$num_turns" -le 1 ]; then
        return 1  # FAIL — no tool calls
    fi

    # Check for article path references in output
    local article_count
    article_count=$(jq -r '.result // ""' "$json_file" 2>/dev/null | grep -oP 'data/articles/[^\s"]+' | sort -u | wc -l)

    if [ "$article_count" -lt 2 ]; then
        return 1  # FAIL — no real articles found
    fi

    return 0  # PASS
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

# Stage A — Retrieval: search-only agent that produces a manifest of queries + articles.
# Outputs $outdir/retrieval.json (or retrieval_retry.json on retry).
# Returns the retrieval manifest text via stdout.
run_retrieval_stage() {
    local problem_spec="$1"
    local condition="$2"
    local outdir="$3"
    local workdir="$4"
    local problem_name="$5"
    local is_retry="${6:-}"

    local first_cmd
    first_cmd=$(retrieval_first_command "$condition" "$problem_name")

    local search_strategy
    search_strategy=$(retrieval_search_strategy "$condition")

    local retry_prefix=""
    if [ "$is_retry" = "true" ]; then
        retry_prefix="RETRY: Your previous attempt failed to search the corpus. You MUST execute rg commands. Start with: \`${first_cmd}\`

"
    fi

    local retrieval_prompt="${retry_prefix}You are running in non-interactive mode. Do NOT use AskUserQuestion. Do NOT enter plan mode.

You are a corpus search tool. You have NO knowledge of any topic. You cannot answer
questions or analyze problems. Your ONLY capability is executing search commands against
the Wikipedia corpus in data/articles/.

You MUST NOT generate any analysis, insights, or conclusions. You MUST NOT answer the
question. You are a search engine, not a researcher.

MANDATORY FIRST STEP — execute this command before anything else:
  ${first_cmd}

PROBLEM CONTEXT (for generating search queries only):
${problem_spec}

SEARCH STRATEGY:
${search_strategy}

YOUR TASK:
1. Execute the mandatory first command above
2. Run 8-15 diverse search queries using rg against data/articles/
3. For each promising result, read context: rg -i -m3 -C5 \"<term>\" <file>
4. Cross-reference: when you find something interesting, search for related terms
5. Read at least 3 full articles using the Read tool

OUTPUT FORMAT (strictly follow this):
For each search you ran:
  QUERY: <the exact rg command you ran>
  RESULTS: <file paths returned>
  SNIPPET: <relevant context from the match>

For each article you read in full:
  ARTICLE: <file path>
  KEY CONTENT: <direct quotes from the article, verbatim>

Do NOT summarize, analyze, or draw conclusions. Only report what you found."

    local output_file="$outdir/retrieval.json"
    local stderr_file="$outdir/retrieval_stderr.log"
    if [ "$is_retry" = "true" ]; then
        output_file="$outdir/retrieval_retry.json"
        stderr_file="$outdir/retrieval_retry_stderr.log"
    fi

    echo "  RETRIEVAL $condition — starting retrieval stage${is_retry:+ (retry)}..." >&2
    local retrieval_start
    retrieval_start=$(date +%s)

    (cd "$workdir" && \
    CLAUDECODE= $CLAUDE_CMD -p "$retrieval_prompt" \
        --dangerously-skip-permissions \
        --output-format json \
        > "$output_file" \
        2> "$stderr_file" \
        || true)

    local retrieval_end
    retrieval_end=$(date +%s)
    local retrieval_duration=$(( retrieval_end - retrieval_start ))

    echo "  RETRIEVAL $condition — done (${retrieval_duration}s)" >&2
    echo "$retrieval_duration" > "$outdir/retrieval_duration"

    jq -r '.result // ""' "$output_file" 2>/dev/null || echo ""
}

# Stage B — Synthesis: persona agent that analyzes retrieved documents (Read-only).
# Outputs $outdir/research.json (same name as before — downstream unchanged).
# Returns the research text via stdout.
run_synthesis_stage() {
    local problem_spec="$1"
    local condition="$2"
    local outdir="$3"
    local workdir="$4"
    local retrieval_manifest="$5"

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

    local synthesis_prompt="You are running in non-interactive mode. Do NOT use AskUserQuestion. Do NOT enter plan mode.
Do NOT write any code.

${agent_system_prompt}

---

RETRIEVED DOCUMENTS:
The following articles and passages were found by searching the Wikipedia corpus.
These are your ONLY source of information. Do NOT introduce facts, algorithms, or
concepts that are not present in the retrieved articles below.

${retrieval_manifest}

---

PROBLEM TO ANALYZE:
${problem_spec}

---

INSTRUCTIONS:
1. ${research_instruction}
2. You may use the Read tool to read any of the article files listed above in full
3. Base your findings ONLY on the retrieved documents
4. Produce structured findings following your Output Shape format
5. For every claim, cite the specific article file path"

    echo "  SYNTHESIS $condition — starting synthesis stage..." >&2
    local synthesis_start
    synthesis_start=$(date +%s)

    (cd "$workdir" && \
    CLAUDECODE= $CLAUDE_CMD -p "$synthesis_prompt" \
        --dangerously-skip-permissions \
        --tools "Read" \
        --output-format json \
        > "$outdir/research.json" \
        2> "$outdir/synthesis_stderr.log" \
        || true)

    local synthesis_end
    synthesis_end=$(date +%s)
    local synthesis_duration=$(( synthesis_end - synthesis_start ))

    echo "  SYNTHESIS $condition — done (${synthesis_duration}s)" >&2
    echo "$synthesis_duration" > "$outdir/synthesis_duration"

    jq -r '.result // ""' "$outdir/research.json" 2>/dev/null || echo ""
}

# Run the full research pipeline: retrieval → verify → synthesis.
# Produces $outdir/research.json with the final research findings.
# Returns the research text via stdout (caller captures it).
run_research_phase() {
    local problem_spec="$1"
    local condition="$2"
    local outdir="$3"
    local workdir="$4"
    local problem_name="$5"

    # Stage A: Retrieval
    echo "  RESEARCH $condition — starting research phase (retrieval → synthesis)..." >&2
    local research_start
    research_start=$(date +%s)

    local retrieval_text
    retrieval_text=$(run_retrieval_stage "$problem_spec" "$condition" "$outdir" "$workdir" "$problem_name")

    local retrieval_retry="false"

    # Verify retrieval produced real results
    local retrieval_file="$outdir/retrieval.json"
    if ! verify_retrieval "$retrieval_file"; then
        echo "  RETRIEVAL $condition — verification FAILED, retrying..." >&2
        retrieval_retry="true"
        retrieval_text=$(run_retrieval_stage "$problem_spec" "$condition" "$outdir" "$workdir" "$problem_name" "true")

        # Use retry output if it exists, otherwise fall back to original
        if [ -f "$outdir/retrieval_retry.json" ]; then
            retrieval_file="$outdir/retrieval_retry.json"
        fi
    fi

    # Stage B: Synthesis
    local research_text
    research_text=$(run_synthesis_stage "$problem_spec" "$condition" "$outdir" "$workdir" "$retrieval_text")

    local research_end
    research_end=$(date +%s)
    local research_duration=$(( research_end - research_start ))

    # Write metadata for caller
    echo "$research_duration" > "$outdir/research_duration"
    echo "$retrieval_retry" > "$outdir/retrieval_retry_flag"

    # Extract retrieval turns for meta.json
    local retrieval_turns
    retrieval_turns=$(jq -r '.num_turns // 0' "$retrieval_file" 2>/dev/null || echo "0")
    echo "$retrieval_turns" > "$outdir/retrieval_turns"

    echo "  RESEARCH $condition — done (${research_duration}s, retrieval_turns=${retrieval_turns}, retry=${retrieval_retry})" >&2

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
        research_text=$(run_research_phase "$prompt" "$condition" "$outdir" "$workdir" "$problem_name")
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

    if [ "$research_duration" -gt 0 ]; then
        echo "  RUN  $problem_name/$condition (coding phase — research took ${research_duration}s)"
    else
        echo "  RUN  $problem_name/$condition"
    fi
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

    # Read retrieval metadata (written by run_research_phase)
    local retrieval_turns
    retrieval_turns=$(cat "$outdir/retrieval_turns" 2>/dev/null || echo "0")
    local retrieval_retry
    retrieval_retry=$(cat "$outdir/retrieval_retry_flag" 2>/dev/null || echo "false")
    local retrieval_duration
    retrieval_duration=$(cat "$outdir/retrieval_duration" 2>/dev/null || echo "0")
    local synthesis_duration
    synthesis_duration=$(cat "$outdir/synthesis_duration" 2>/dev/null || echo "0")

    # Record metadata
    cat > "$outdir/meta.json" << METAEOF
{
    "problem": "$problem_name",
    "condition": "$condition",
    "retrieval_duration_seconds": $retrieval_duration,
    "retrieval_retry": $retrieval_retry,
    "retrieval_turns": $retrieval_turns,
    "synthesis_duration_seconds": $synthesis_duration,
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
