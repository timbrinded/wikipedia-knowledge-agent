# Problem 8: CSV Parser

Implement a CSV parser in Python from scratch (do not use the `csv` module or pandas). It must handle:

- Comma-separated values
- Quoted fields (fields containing commas, newlines, or quotes)
- Escaped quotes within quoted fields (`""` inside quotes)
- Different line endings (`\n`, `\r\n`, `\r`)
- Empty fields
- Header row detection

Provide both a parser function and a writer function:
- `parse(text: str) -> list[dict]` — parse CSV text, return list of dicts keyed by header
- `write(records: list[dict]) -> str` — write dicts back to CSV text

Round-tripping should be lossless: `parse(write(parse(text)))` == `parse(text)`.

Include tests with edge cases.

## Deliverable

Write all code to a `csv_parser/` directory.
