"""invoice_tools.validators — row validation and currency normalization.

Both functions return a NEW dict rather than mutating the row in place —
a deliberate fix: dedupe_invoices() runs right after validation in
main.py's pipeline and was seeing already-mutated rows before this.
"""


def normalize_currency(row):
    row = dict(row)
    row["amount"] = round(float(row["amount"]), 2)
    return row


def validate_invoice_row(row):
    row = dict(row)
    if not row.get("invoice_id"):
        raise ValueError("invoice row missing invoice_id")
    if not row.get("vendor"):
        raise ValueError("invoice row missing vendor")
    if row.get("amount", 0) < 0:
        raise ValueError(f"invoice {row['invoice_id']} has negative amount")
    return row
