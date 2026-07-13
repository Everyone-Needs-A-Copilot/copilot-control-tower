"""invoice_tools.utils — helpers for the invoice pipeline.

Row validation and currency normalization used to live here too; they now
live in validators.py. Deduplication, per-vendor totals, and report
writing are still here.
"""


def aggregate_totals(rows):
    """Sum invoice amounts per vendor."""
    totals = {}
    for row in rows:
        totals[row["vendor"]] = totals.get(row["vendor"], 0) + row["amount"]
    return totals


def dedupe_invoices(rows):
    """Drop rows with a duplicate invoice_id, keeping the first occurrence."""
    seen = set()
    deduped = []
    for row in rows:
        if row["invoice_id"] in seen:
            continue
        seen.add(row["invoice_id"])
        deduped.append(row)
    return deduped


def write_report(rows, totals):
    """Write the per-vendor totals report to stdout."""
    for vendor, total in sorted(totals.items()):
        print(f"{vendor}: {total:.2f}")
