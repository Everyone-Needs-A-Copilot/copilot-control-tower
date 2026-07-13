"""invoice_tools — CLI entry point for the invoice-processing pipeline.

Reads a batch of invoice rows, validates + normalizes them, dedupes and
totals them per vendor, then writes a report.
"""
import csv
import sys

from validators import normalize_currency, validate_invoice_row
from utils import aggregate_totals, dedupe_invoices, write_report


def load_rows(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def run(path):
    rows = load_rows(path)
    rows = [validate_invoice_row(normalize_currency(row)) for row in rows]
    rows = dedupe_invoices(rows)
    totals = aggregate_totals(rows)
    write_report(rows, totals)


if __name__ == "__main__":
    run(sys.argv[1])
