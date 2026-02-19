#!/usr/bin/env bash
set -euo pipefail

# Download and extract English Wikipedia to flat text files.
#
# Wikipedia publishes article dumps in XML. We use WikiExtractor to convert
# to plain text, then split into one file per article.
#
# Requirements: uv, curl/wget, bzip2
# Disk: ~22GB compressed download, ~90GB extracted text

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${WIKIPEDIA_DATA_DIR:-$PROJECT_DIR/data}"
DUMP_DIR="$DATA_DIR/dump"
ARTICLES_DIR="$DATA_DIR/articles"

DUMP_URL="https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2"
DUMP_FILE="$DUMP_DIR/enwiki-latest-pages-articles.xml.bz2"

echo "=== Wikipedia Knowledge Agent — Download & Extract ==="
echo "Data directory: $DATA_DIR"
echo ""

mkdir -p "$DUMP_DIR" "$ARTICLES_DIR"

# --- Step 1: Download dump ---
if [ -f "$DUMP_FILE" ]; then
    echo "[1/3] Dump already downloaded: $DUMP_FILE"
    echo "      Size: $(du -h "$DUMP_FILE" | cut -f1)"
else
    echo "[1/3] Downloading Wikipedia dump (~22GB)..."
    echo "      URL: $DUMP_URL"
    echo "      This will take a while."
    curl -L -o "$DUMP_FILE" --progress-bar "$DUMP_URL"
    echo "      Done. Size: $(du -h "$DUMP_FILE" | cut -f1)"
fi

# --- Step 2: Extract to text ---
EXTRACTED_DIR="$DATA_DIR/extracted"
if [ -d "$EXTRACTED_DIR" ] && [ "$(find "$EXTRACTED_DIR" -name "wiki_*" | head -1)" ]; then
    echo "[2/3] Extraction already done: $EXTRACTED_DIR"
else
    echo "[2/3] Extracting articles to plain text..."
    echo "      This takes 2-4 hours. Output: $EXTRACTED_DIR"
    mkdir -p "$EXTRACTED_DIR"
    uv run wikiextractor \
        "$DUMP_FILE" \
        --output "$EXTRACTED_DIR" \
        --json \
        --processes "$(nproc)" \
        --quiet
    echo "      Extraction complete."
fi

# --- Step 3: Split into one file per article ---
if [ "$(find "$ARTICLES_DIR" -name "*.txt" | head -1)" ]; then
    ARTICLE_COUNT=$(find "$ARTICLES_DIR" -name "*.txt" | wc -l)
    echo "[3/3] Articles already split: $ARTICLE_COUNT files in $ARTICLES_DIR"
else
    echo "[3/3] Splitting into one file per article..."
    echo "      Output: $ARTICLES_DIR"
    uv run split-articles "$EXTRACTED_DIR" "$ARTICLES_DIR"
fi

echo ""
echo "=== Setup complete ==="
echo "Articles: $ARTICLES_DIR"
echo "Run ./setup/build-index.sh next to create search indexes."
