#!/usr/bin/env bash
set -euo pipefail

# Build greppable indexes from extracted Wikipedia articles.
#
# Creates:
#   data/index/titles.txt      — "slug<TAB>Original Title"
#   data/index/paths.txt       — "slug<TAB>Original Title<TAB>filepath"
#   data/index/categories.txt  — "Category Name<TAB>count"
#
# Designed for millions of articles. Uses Python readline (no subprocess per
# file) for title extraction and streaming XML parse for categories.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"
ARTICLES_DIR="$DATA_DIR/articles"
DUMP_DIR="$DATA_DIR/dump"
DUMP_FILE="$DUMP_DIR/enwiki-latest-pages-articles.xml.bz2"
INDEX_DIR="$DATA_DIR/index"

# Keep sort temp files off RAM-backed tmpfs — use disk-backed /var/tmp
export TMPDIR=/var/tmp

echo "=== Building search indexes ==="

if [ ! -d "$ARTICLES_DIR" ]; then
    echo "Error: Articles directory not found: $ARTICLES_DIR"
    echo "Run ./setup/download-wikipedia.sh first."
    exit 1
fi

mkdir -p "$INDEX_DIR"

ARTICLE_COUNT=$(find "$ARTICLES_DIR" -name "*.txt" | wc -l)
echo "Articles found: $ARTICLE_COUNT"
echo ""

# --- Step 1: Title + Path index (single pass, no subprocess per file) ---
echo "[1/2] Building title and path indexes..."

find "$ARTICLES_DIR" -name "*.txt" | python3 -c "
import sys, os

count = 0
for line in sys.stdin:
    filepath = line.rstrip('\n')
    slug = os.path.basename(filepath)[:-4]  # strip .txt
    try:
        with open(filepath) as f:
            title = f.readline().strip().lstrip('# ')
    except (IOError, OSError):
        continue
    sys.stdout.write(f'{slug}\t{title}\t{filepath}\n')
    count += 1
    if count % 1_000_000 == 0:
        print(f'      {count:,} articles processed...', file=sys.stderr)
print(f'      {count:,} articles total.', file=sys.stderr)
" | LC_ALL=C sort > "$INDEX_DIR/paths.txt"

# Derive titles-only index from paths (fast awk, no re-read)
awk -F'\t' '{print $1 "\t" $2}' "$INDEX_DIR/paths.txt" > "$INDEX_DIR/titles.txt"

TITLE_COUNT=$(wc -l < "$INDEX_DIR/titles.txt")
echo "      $TITLE_COUNT titles indexed."
echo ""

# --- Step 2: Category index (from raw XML dump) ---
echo "[2/2] Building category index from XML dump..."

if [ ! -f "$DUMP_FILE" ]; then
    echo "Warning: Dump file not found: $DUMP_FILE"
    echo "Skipping category index. Re-run after downloading the dump."
    CAT_COUNT=0
else
    # Prefer lbzip2 (parallel) over bzip2 (single-threaded) for decompression
    if command -v lbzip2 &>/dev/null; then
        BZCAT="lbzip2 -dc"
    else
        BZCAT="bzip2 -dc"
    fi

    $BZCAT "$DUMP_FILE" | python3 "$PROJECT_DIR/scripts/build_categories.py" | \
        cut -f2 | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn | \
        awk '{$1=$1; count=$1; $1=""; print substr($0,2) "\t" count}' \
        > "$INDEX_DIR/categories.txt"

    CAT_COUNT=$(wc -l < "$INDEX_DIR/categories.txt")
fi
echo "      $CAT_COUNT unique categories indexed."

echo ""
echo "=== Indexes built ==="
echo "  Titles:     $INDEX_DIR/titles.txt ($TITLE_COUNT entries)"
echo "  Categories: $INDEX_DIR/categories.txt ($CAT_COUNT entries)"
echo "  Paths:      $INDEX_DIR/paths.txt"
echo ""
echo "Ready for experiments."
