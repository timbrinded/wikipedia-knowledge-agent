"""Split WikiExtractor output into one text file per article."""

import argparse
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


def split(extracted_dir: str, articles_dir: str) -> None:
    """Walk extracted wiki files and write one .txt per article."""
    count = 0
    for root, _dirs, files in os.walk(extracted_dir):
        for fname in sorted(files):
            if not fname.startswith("wiki_"):
                continue
            filepath = os.path.join(root, fname)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()

            for match in re.finditer(
                r'<doc id="(\d+)" url="([^"]*)" title="([^"]*)">\n(.*?)</doc>',
                content, re.DOTALL,
            ):
                _doc_id, _url, title, body = match.groups()
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
