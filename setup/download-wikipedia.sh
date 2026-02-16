#!/usr/bin/env bash
set -euo pipefail

# Download and extract English Wikipedia to flat text files.
#
# Wikipedia publishes article dumps in XML. We use WikiExtractor to convert
# to plain text, then split into one file per article.
#
# Requirements: python3, pip (WikiExtractor), curl/wget, bzip2
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
    echo "[1/4] Dump already downloaded: $DUMP_FILE"
    echo "      Size: $(du -h "$DUMP_FILE" | cut -f1)"
else
    echo "[1/4] Downloading Wikipedia dump (~22GB)..."
    echo "      URL: $DUMP_URL"
    echo "      This will take a while."
    curl -L -o "$DUMP_FILE" --progress-bar "$DUMP_URL"
    echo "      Done. Size: $(du -h "$DUMP_FILE" | cut -f1)"
fi

# --- Step 2: Install WikiExtractor ---
echo "[2/4] Ensuring WikiExtractor is installed..."
if ! python3 -m wikiextractor --help &>/dev/null; then
    echo "      Installing WikiExtractor..."
    pip3 install --quiet wikiextractor
fi
echo "      WikiExtractor ready."

# --- Step 3: Extract to text ---
EXTRACTED_DIR="$DATA_DIR/extracted"
if [ -d "$EXTRACTED_DIR" ] && [ "$(find "$EXTRACTED_DIR" -name "wiki_*" | head -1)" ]; then
    echo "[3/4] Extraction already done: $EXTRACTED_DIR"
else
    echo "[3/4] Extracting articles to plain text..."
    echo "      This takes 2-4 hours. Output: $EXTRACTED_DIR"
    mkdir -p "$EXTRACTED_DIR"
    python3 -m wikiextractor.WikiExtractor \
        "$DUMP_FILE" \
        --output "$EXTRACTED_DIR" \
        --bytes 0 \
        --no-templates \
        --processes "$(nproc)" \
        --quiet
    echo "      Extraction complete."
fi

# --- Step 4: Split into one file per article ---
if [ "$(find "$ARTICLES_DIR" -name "*.txt" | head -1)" ]; then
    ARTICLE_COUNT=$(find "$ARTICLES_DIR" -name "*.txt" | wc -l)
    echo "[4/4] Articles already split: $ARTICLE_COUNT files in $ARTICLES_DIR"
else
    echo "[4/4] Splitting into one file per article..."
    echo "      Output: $ARTICLES_DIR"

    python3 << 'PYEOF'
import os
import re
import sys

extracted_dir = os.environ.get("EXTRACTED_DIR", "data/extracted")
articles_dir = os.environ.get("ARTICLES_DIR", "data/articles")

def slugify(title):
    """Convert article title to safe filename."""
    slug = title.strip().lower()
    slug = re.sub(r'[^\w\s-]', '', slug)
    slug = re.sub(r'[\s_]+', '_', slug)
    slug = slug.strip('_')
    return slug[:200]  # cap length

count = 0
for root, dirs, files in os.walk(extracted_dir):
    for fname in sorted(files):
        if not fname.startswith("wiki_"):
            continue
        filepath = os.path.join(root, fname)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # WikiExtractor wraps each article in <doc> tags
        for match in re.finditer(
            r'<doc id="(\d+)" url="([^"]*)" title="([^"]*)">\n(.*?)</doc>',
            content, re.DOTALL
        ):
            doc_id, url, title, body = match.groups()
            body = body.strip()
            if not body or len(body) < 50:
                continue  # skip stubs

            slug = slugify(title)
            if not slug:
                continue

            # Use first 2 chars as subdirectory for filesystem sanity
            subdir = slug[:2] if len(slug) >= 2 else slug
            outdir = os.path.join(articles_dir, subdir)
            os.makedirs(outdir, exist_ok=True)

            outpath = os.path.join(outdir, f"{slug}.txt")
            with open(outpath, 'w', encoding='utf-8') as out:
                out.write(f"# {title}\n\n")
                out.write(body)
                out.write("\n")

            count += 1
            if count % 100000 == 0:
                print(f"      {count:,} articles written...", file=sys.stderr)

print(f"      Done. {count:,} articles written to {articles_dir}", file=sys.stderr)
PYEOF

fi

echo ""
echo "=== Setup complete ==="
echo "Articles: $ARTICLES_DIR"
echo "Run ./setup/build-index.sh next to create search indexes."
