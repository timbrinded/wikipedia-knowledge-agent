"""Strip comments from Python source code using the tokenizer.

Reads from stdin, writes comment-free code to stdout.
Falls back to passthrough on parse errors (e.g. non-Python content).
"""

import io
import sys
import tokenize


def strip_comments(source: str) -> str:
    lines = source.splitlines(True)
    # Collect (line_index, col) for each comment token
    comment_positions: list[tuple[int, int]] = []
    try:
        for tok in tokenize.generate_tokens(io.StringIO(source).readline):
            if tok.type == tokenize.COMMENT:
                comment_positions.append((tok.start[0] - 1, tok.start[1]))
    except tokenize.TokenError:
        return source  # unparseable — return unchanged

    # Truncate each line at the comment start
    for line_idx, col in reversed(comment_positions):
        if line_idx < len(lines):
            lines[line_idx] = lines[line_idx][:col].rstrip() + "\n"

    # Drop blank lines
    return "".join(line for line in lines if line.strip())


if __name__ == "__main__":
    sys.stdout.write(strip_comments(sys.stdin.read()))
