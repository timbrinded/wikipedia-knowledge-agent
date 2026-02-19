"""Extract categories from a Wikipedia XML dump (streamed via stdin).

Reads decompressed XML from stdin, extracts [[Category:...]] from each
page's wikitext, and outputs one line per (slug, category) pair:

    slug\tCategory Name

Pipe through sort | uniq -c | sort -rn to get category counts.

Usage:
    bzip2 -dc dump.xml.bz2 | python3 scripts/build_categories.py
"""

import re
import sys
import xml.etree.ElementTree as ET

CATEGORY_RE = re.compile(r'\[\[Category:([^\]|]+)')
NS = '{http://www.mediawiki.org/xml/export-0.11/}'


def slugify(title: str) -> str:
    """Convert article title to safe filename (matches split_articles.py)."""
    slug = title.strip().lower()
    slug = re.sub(r'[^\w\s-]', '', slug)
    slug = re.sub(r'[\s_]+', '_', slug)
    slug = slug.strip('_')
    return slug[:200]


def main() -> None:
    count = 0
    pairs = 0

    for _, elem in ET.iterparse(sys.stdin, events=('end',)):
        if elem.tag != f'{NS}page':
            continue

        ns_elem = elem.find(f'{NS}ns')
        if ns_elem is None or ns_elem.text != '0':
            elem.clear()
            continue

        title_elem = elem.find(f'{NS}title')
        text_elem = elem.find(f'.//{NS}text')

        if title_elem is None or title_elem.text is None or text_elem is None or not text_elem.text:
            elem.clear()
            continue

        title = title_elem.text
        slug = slugify(title)
        if not slug:
            elem.clear()
            continue

        for match in CATEGORY_RE.finditer(text_elem.text):
            cat = match.group(1).strip()
            if cat:
                sys.stdout.write(f'{slug}\t{cat}\n')
                pairs += 1

        count += 1
        if count % 1_000_000 == 0:
            print(f'      {count:,} pages, {pairs:,} category pairs...', file=sys.stderr)

        elem.clear()

    print(f'      Done. {count:,} pages, {pairs:,} category pairs.', file=sys.stderr)


if __name__ == '__main__':
    main()
