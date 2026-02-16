#!/usr/bin/env bash
set -euo pipefail

# Build greppable indexes from extracted Wikipedia articles.
#
# Creates:
#   data/index/titles.txt      — one line per article: "slug<TAB>Original Title"
#   data/index/categories.txt  — one line per: "slug<TAB>Category Name"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"
ARTICLES_DIR="$DATA_DIR/articles"
INDEX_DIR="$DATA_DIR/index"

echo "=== Building search indexes ==="

if [ ! -d "$ARTICLES_DIR" ]; then
    echo "Error: Articles directory not found: $ARTICLES_DIR"
    echo "Run ./setup/download-wikipedia.sh first."
    exit 1
fi

mkdir -p "$INDEX_DIR"

# --- Title index ---
echo "[1/2] Building title index..."
TITLES_FILE="$INDEX_DIR/titles.txt"

find "$ARTICLES_DIR" -name "*.txt" -print0 | \
    xargs -0 -P "$(nproc)" -I{} head -1 {} | \
    sed 's/^# //' | \
    sort > "$TITLES_FILE.tmp"

# Also build a slug→path mapping for fast article lookup
echo "      Building path index..."
find "$ARTICLES_DIR" -name "*.txt" | while read -r filepath; do
    title=$(head -1 "$filepath" | sed 's/^# //')
    slug=$(basename "$filepath" .txt)
    echo "${slug}	${title}	${filepath}"
done | sort > "$INDEX_DIR/paths.txt"

# Simple title-only index for fast grep
awk -F'\t' '{print $1 "\t" $2}' "$INDEX_DIR/paths.txt" > "$TITLES_FILE"
rm -f "$TITLES_FILE.tmp"

TITLE_COUNT=$(wc -l < "$TITLES_FILE")
echo "      $TITLE_COUNT titles indexed."

# --- Category index ---
echo "[2/2] Building category index..."
CATEGORIES_FILE="$INDEX_DIR/categories.txt"

# Extract category references from article content
# Wikipedia articles mention categories inline as [[Category:Name]]
find "$ARTICLES_DIR" -name "*.txt" -print0 | \
    xargs -0 -P "$(nproc)" grep -h -oP '\[\[Category:([^\]]+)\]\]' 2>/dev/null | \
    sed 's/\[\[Category://;s/\]\]//' | \
    sort | uniq -c | sort -rn | \
    awk '{$1=$1; count=$1; $1=""; print substr($0,2) "\t" count}' > "$CATEGORIES_FILE"

CAT_COUNT=$(wc -l < "$CATEGORIES_FILE")
echo "      $CAT_COUNT unique categories indexed."

echo ""
echo "=== Indexes built ==="
echo "  Titles:     $TITLES_FILE ($TITLE_COUNT entries)"
echo "  Categories: $CATEGORIES_FILE ($CAT_COUNT entries)"
echo "  Paths:      $INDEX_DIR/paths.txt"
echo ""
echo "Ready for experiments. See skill/SKILL.md for agent usage."
