"""calc.py — fixture for ladder job-1-bugfix (TASK-125 / W-3).

A tiny, self-contained calculator module with ONE deliberate bug. This is
the ladder's smallest job (PRD phase-4-outcome-program-prd.md par.3 W-3:
"an R-series fix implemented 4 ways") — graduated size: small.

The bug: average() divides by len(numbers) - 1 instead of len(numbers), an
off-by-one that gives a wrong (or, for single-item lists, a crashing
ZeroDivisionError) result. See test_calc.py for the acceptance tests the
fix must satisfy.
"""


def add(a, b):
    return a + b


def subtract(a, b):
    return a - b


def average(numbers):
    """Return the arithmetic mean of a non-empty list of numbers.

    BUG (fix this): divides by len(numbers) - 1 instead of len(numbers).
    """
    return sum(numbers) / (len(numbers) - 1)
