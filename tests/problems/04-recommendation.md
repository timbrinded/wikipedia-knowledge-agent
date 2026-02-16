# Problem 4: Recommendation System That Avoids Filter Bubbles

Design and implement a recommendation engine in Python that actively works to avoid filter bubbles. It should balance relevance (recommending things the user will like) with diversity (exposing the user to new perspectives and topics).

## Requirements

- Content items with tags/categories and a quality score
- User profiles built from interaction history (views, likes, skips)
- Recommendation scoring that balances relevance and novelty
- A measurable "diversity score" for any set of recommendations
- Configurable exploration vs exploitation trade-off
- Simulation showing that recommendations maintain diversity over time rather than converging

## Deliverable

A working Python implementation with:
1. The recommendation engine with your diversity-aware algorithm
2. A baseline relevance-only recommender for comparison
3. Simulated users with different browsing patterns
4. Charts or metrics showing diversity scores over time for both approaches

Write all code to a `recommendation/` directory.
