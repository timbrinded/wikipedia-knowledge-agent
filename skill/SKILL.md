# Wikipedia Knowledge Base

You have access to the entirety of English Wikipedia (~6.8 million articles) stored locally as plain text files. You can search and read any article using standard tools.

## Available Tools

### Search article titles
```bash
rg -i "<query>" data/index/titles.txt | head -20
```
Fast lookup across all article titles. Good for finding specific topics.

### Search categories
```bash
rg -i "<query>" data/index/categories.txt | head -20
```
Find broad topic areas and how articles are categorised.

### Read a specific article
```bash
# Find the path first
rg -m1 "^<slug>\t" data/index/paths.txt | cut -f3
# Then read it
cat <path>
```

### Search across all article content
```bash
rg -l -i "<query>" data/articles/ | head -20        # find articles containing term
rg -i -C2 "<query>" data/articles/<subdir>/<file>    # see context within article
```
Searches the full text of all articles. Powerful but slower — use title/category search first to narrow down, then grep content when you need depth.

### Explore a topic area
```bash
ls data/articles/<two-letter-prefix>/                 # browse articles by name prefix
rg -l -i "<broad term>" data/articles/ | wc -l       # how many articles mention a term
```

## Tips

- Start broad (title/category search), then narrow (content grep)
- Wikipedia articles are plain text with `# Title` as the first line
- Articles are stored in subdirectories by first two characters of their slug
- Cross-reference multiple articles to build understanding
- Category search helps discover related topics you might not think to search for
