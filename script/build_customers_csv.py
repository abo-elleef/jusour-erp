#!/usr/bin/env python3
"""
Clean + merge the two legacy customer exports (normal_customers.xlsx, vip_customers.xlsx)
into one import-ready CSV for the SAQR POS `customers` / `customer_addresses` tables.

Source files are raw exports from an old Arabic accounting/POS system: no header row,
lots of merged/duplicated cells, Arabic-Indic digits in phone numbers, and a "notes"
column that occasionally hides a misplaced phone number. This script normalizes all of
that and produces:

  customers_export.csv          -> one row per unique customer, ready to import
  customers_needs_review.csv    -> rows with no usable phone number at all (can't be
                                    uniquely identified / imported automatically)

Usage:
  python3 build_customers_csv.py normal_customers.xlsx vip_customers.xlsx
"""
import sys
import re
import csv
import openpyxl
from collections import OrderedDict

ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
BIDI_CHARS = re.compile(r"[‎‏⁦⁧⁨⁩]")
EGY_MOBILE_RE = re.compile(r"^01[0-25]\d{8}$")


def clean_text(v):
    if v is None:
        return ""
    return str(v).strip()


def normalize_phone_raw(v):
    """Digit-only normalization (Arabic->Western digits, strip bidi marks/spaces/punct)."""
    if v is None:
        return ""
    s = str(v).translate(ARABIC_DIGITS)
    s = BIDI_CHARS.sub("", s)
    s = s.strip()
    if not s:
        return ""
    s = re.sub(r"[^0-9+]", "", s)
    if s.startswith("+20"):
        s = "0" + s[3:]
    elif s.startswith("0020"):
        s = "0" + s[4:]
    elif s.startswith("20") and len(s) == 12:
        s = "0" + s[2:]
    s = re.sub(r"[^0-9]", "", s)
    if len(s) == 10 and s.startswith("1"):
        s = "0" + s
    return s


def phone_format_ok(p):
    return bool(EGY_MOBILE_RE.match(p))


def looks_like_phone(v):
    p = normalize_phone_raw(v)
    return p if phone_format_ok(p) else None


def load_rows(path, customer_type):
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb["Page1"]
    out = []
    for r in ws.iter_rows(min_row=1, values_only=True):
        if not any(c is not None for c in r):
            continue
        name = clean_text(r[2])
        phone_raw = r[6]
        alt_phone_raw = r[16]
        notes = clean_text(r[24])
        balance = r[22]
        legacy_id = r[26]

        phone = normalize_phone_raw(phone_raw)
        recovered_from_notes = False
        if not phone:
            recovered = looks_like_phone(notes)
            if recovered:
                phone = recovered
                recovered_from_notes = True

        alt_phone = normalize_phone_raw(alt_phone_raw)
        if alt_phone == phone:
            alt_phone = ""

        out.append({
            "name": name,
            "phone": phone,
            "phone_format_ok": phone_format_ok(phone) if phone else False,
            "phone_recovered_from_notes": recovered_from_notes,
            "alt_phone": alt_phone,
            "customer_type": customer_type,
            "balance": balance if isinstance(balance, (int, float)) else None,
            "legacy_id": legacy_id,
            "notes_raw": notes,
        })
    return out


def merge(rows):
    """Group by normalized phone. VIP wins over normal on conflicting type."""
    by_phone = OrderedDict()
    no_phone = []

    for r in rows:
        if not r["phone"]:
            no_phone.append(r)
            continue
        key = r["phone"]
        if key not in by_phone:
            by_phone[key] = {
                "phone": key,
                "names": OrderedDict(),
                "phone_secondary": "",
                "customer_type": r["customer_type"],
                "balance_total": 0.0,
                "legacy_ids": [],
                "row_count": 0,
                "phone_format_ok": r["phone_format_ok"],
                "recovered_count": 0,
            }
        bucket = by_phone[key]
        if r["name"]:
            bucket["names"][r["name"]] = bucket["names"].get(r["name"], 0) + 1
        if r["alt_phone"] and not bucket["phone_secondary"]:
            bucket["phone_secondary"] = r["alt_phone"]
        if r["customer_type"] == "vip":
            bucket["customer_type"] = "vip"
        if r["balance"]:
            bucket["balance_total"] += r["balance"]
        if r["legacy_id"] is not None:
            bucket["legacy_ids"].append(str(r["legacy_id"]))
        if r["phone_recovered_from_notes"]:
            bucket["recovered_count"] += 1
        bucket["row_count"] += 1

    return by_phone, no_phone


def main():
    if len(sys.argv) != 3:
        print("Usage: build_customers_csv.py normal_customers.xlsx vip_customers.xlsx")
        sys.exit(1)

    normal_path, vip_path = sys.argv[1], sys.argv[2]

    all_rows = load_rows(normal_path, "normal") + load_rows(vip_path, "vip")
    by_phone, no_phone = merge(all_rows)

    export_path = "customers_export.csv"
    review_path = "customers_needs_review.csv"

    with open(export_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "name", "phone", "phone_secondary", "address", "extra_addresses",
            "customer_type", "phone_format_ok", "legacy_balance_egp",
            "legacy_ids", "source_row_count",
        ])
        for key, b in by_phone.items():
            names = list(b["names"].keys())
            primary_name = names[0] if names else ""
            extra = "; ".join(names[1:]) if len(names) > 1 else ""
            w.writerow([
                primary_name,
                b["phone"],
                b["phone_secondary"],
                primary_name,  # address == name in the source data (delivery area, not a person's name)
                extra,
                b["customer_type"],
                "yes" if b["phone_format_ok"] else "no",
                f"{b['balance_total']:.2f}" if b["balance_total"] else "",
                ",".join(b["legacy_ids"]),
                b["row_count"],
            ])

    with open(review_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["name", "customer_type", "legacy_id", "notes_raw", "balance"])
        for r in no_phone:
            w.writerow([r["name"], r["customer_type"], r["legacy_id"], r["notes_raw"], r["balance"]])

    total_customers = len(by_phone)
    bad_format = sum(1 for b in by_phone.values() if not b["phone_format_ok"])
    recovered = sum(b["recovered_count"] for b in by_phone.values())
    vip_count = sum(1 for b in by_phone.values() if b["customer_type"] == "vip")

    print(f"Source rows read:            {len(all_rows)}")
    print(f"Unique customers (by phone): {total_customers}")
    print(f"  of which VIP:              {vip_count}")
    print(f"  non-standard phone format: {bad_format} (kept, flagged phone_format_ok=no)")
    print(f"  phone recovered from notes col: {recovered}")
    print(f"Rows with no usable phone (skipped, see {review_path}): {len(no_phone)}")
    print(f"Wrote: {export_path}")
    print(f"Wrote: {review_path}")


if __name__ == "__main__":
    main()
