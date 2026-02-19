"""Split WikiExtractor output into one text file per article.

Supports both JSON format (--json flag, one JSON object per line) and
legacy XML format (<doc>...</doc> blocks). JSON is preferred — it streams
line-by-line with constant memory.
"""

import argparse
import json
import os
import re
import sys


def slugify(title: str) -> str:
    """Convert article title to safe filename."""
    slug = title.strip().lower()
    slug = re.sub(r'[^\w\s-]', '', slug)
    slug = re.sub(r'[\s_]+', '_', slug)
    slug = slug.strip('_')
    return slug[:200]


def write_article(articles_dir: str, title: str, body: str) -> bool:
    """Write a single article to disk. Returns True if written."""
    body = body.strip()
    if not body or len(body) < 50:
        return False

    slug = slugify(title)
    if not slug:
        return False

    subdir = slug[:2] if len(slug) >= 2 else slug
    outdir = os.path.join(articles_dir, subdir)
    os.makedirs(outdir, exist_ok=True)

    outpath = os.path.join(outdir, f"{slug}.txt")
    with open(outpath, 'w', encoding='utf-8') as out:
        out.write(f"# {title}\n\n")
        out.write(body)
        out.write("\n")
    return True


def is_json_format(filepath: str) -> bool:
    """Check if a wiki_ file uses JSON format (first line is valid JSON)."""
    with open(filepath, 'r', encoding='utf-8') as f:
        first_line = f.readline().strip()
        if not first_line:
            return False
        try:
            json.loads(first_line)
            return True
        except (json.JSONDecodeError, ValueError):
            return False


def split_json(filepath: str, articles_dir: str) -> int:
    """Stream JSON file line-by-line — constant memory."""
    count = 0
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                doc = json.loads(line)
            except (json.JSONDecodeError, ValueError):
                continue
            title = doc.get("title", "")
            body = doc.get("text", "")
            if write_article(articles_dir, title, body):
                count += 1
    return count


def split_xml(filepath: str, articles_dir: str) -> int:
    """Legacy XML format — reads full file into memory."""
    count = 0
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    for match in re.finditer(
        r'<doc id="(\d+)" url="([^"]*)" title="([^"]*)">\n(.*?)</doc>',
        content, re.DOTALL,
    ):
        _doc_id, _url, title, body = match.groups()
        if write_article(articles_dir, title, body):
            count += 1
    return count


def split(extracted_dir: str, articles_dir: str) -> None:
    """Walk extracted wiki files and write one .txt per article."""
    count = 0
    detected_format = None

    for root, _dirs, files in os.walk(extracted_dir):
        for fname in sorted(files):
            if not fname.startswith("wiki_"):
                continue
            filepath = os.path.join(root, fname)

            # Auto-detect format from first file
            if detected_format is None:
                detected_format = "json" if is_json_format(filepath) else "xml"
                print(f"      Detected {detected_format} format", file=sys.stderr)

            if detected_format == "json":
                count += split_json(filepath, articles_dir)
            else:
                count += split_xml(filepath, articles_dir)

            if count % 100_000 == 0 and count > 0:
                print(f"      {count:,} articles written...", file=sys.stderr)

    print(f"      Done. {count:,} articles written to {articles_dir}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Split WikiExtractor output into one text file per article.",
    )
    parser.add_argument(
        "extracted_dir",
        help="Directory containing WikiExtractor output (wiki_* files)",
    )
    parser.add_argument(
        "articles_dir",
        help="Output directory for individual article .txt files",
    )
    args = parser.parse_args()
    split(args.extracted_dir, args.articles_dir)


if __name__ == "__main__":
    main()
