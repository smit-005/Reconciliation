#!/usr/bin/env python3
"""Generate deterministic synthetic LedgerMatch Excel datasets.

The generator intentionally avoids external dependencies so it can run in a
fresh checkout with the Python standard library only.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import random
import shutil
import tempfile
import zipfile
from collections import Counter
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape


DATASET_SIZES = {
    "smoke": 1_000,
    "medium": 15_000,
    "stress": 75_000,
}

SECTION_WEIGHTS = {
    "194Q": 0.35,
    "194C": 0.35,
    "194H": 0.15,
    "194A": 0.15,
}

TDS_RATES = {
    "194Q": 0.001,
    "194C": 0.01,
    "194H": 0.05,
    "194A": 0.10,
}

BASE_SCENARIO_WEIGHTS = {
    "exact_match": 0.58,
    "amount_mismatch": 0.09,
    "tds_mismatch": 0.06,
    "only_in_26q": 0.06,
    "missing_pan": 0.06,
    "pan_conflict": 0.06,
    "timing_difference": 0.09,
}

SECTION_194Q_SCENARIO_WEIGHTS = {
    "exact_match": 0.45,
    "amount_mismatch": 0.08,
    "tds_mismatch": 0.05,
    "only_in_26q": 0.05,
    "missing_pan": 0.05,
    "pan_conflict": 0.05,
    "timing_difference": 0.07,
    "below_threshold": 0.10,
    "above_threshold": 0.10,
}

ONLY_IN_LEDGER_RATIO = 0.055

FY_START = date(2025, 4, 1)
FY_END = date(2026, 3, 31)
FIXED_ZIP_DATE_TIME = (2025, 4, 1, 0, 0, 0)

TDS_HEADERS = [
    "Date / Month",
    "Party Name",
    "PAN Number",
    "Amount Paid",
    "TDS Amount",
    "Section",
    "Scenario",
    "Synthetic Row Id",
]

PURCHASE_HEADERS = [
    "Bill Date",
    "Bill No",
    "Party Name",
    "PAN Number",
    "GST No",
    "Basic Amount",
    "Bill Amount",
    "TDS Amount",
    "Section",
    "Product Name",
    "Scenario",
    "Synthetic Row Id",
    "Description",
]

GENERIC_LEDGER_HEADERS = [
    "Date",
    "Bill No",
    "Party Name",
    "PAN Number",
    "GST No",
    "Amount",
    "TDS Amount",
    "Section",
    "Description",
    "Scenario",
    "Synthetic Row Id",
]

NAME_LEFT = [
    "Aster",
    "Beryl",
    "Calyx",
    "Davin",
    "Elar",
    "Faron",
    "Garnet",
    "Helio",
    "Ivara",
    "Juno",
    "Kavix",
    "Lumen",
    "Mavora",
    "Nivora",
    "Orbin",
    "Prava",
    "Quanta",
    "Rivon",
    "Solace",
    "Terral",
    "Umbra",
    "Veyra",
    "Wrenix",
    "Xylen",
    "Yorvi",
    "Zentra",
]

NAME_RIGHT = [
    "Axis",
    "Bridge",
    "Crest",
    "Delta",
    "Forge",
    "Harbor",
    "Junction",
    "Keystone",
    "Meridian",
    "Northstar",
    "Orchard",
    "Pinnacle",
    "Quarry",
    "River",
    "Summit",
    "Timber",
    "Union",
    "Vertex",
    "Willow",
    "Yard",
]

NAME_BUSINESS = {
    "194Q": [
        "Components",
        "Packaging",
        "Supply",
        "Metals",
        "Trading",
        "Industrial",
    ],
    "194C": [
        "Contracting",
        "Logistics",
        "Fabrication",
        "Works",
        "Services",
        "Projects",
    ],
    "194H": [
        "Agency",
        "Distribution",
        "Marketing",
        "Brokerage",
        "Outreach",
        "Networks",
    ],
    "194A": [
        "Finance",
        "Capital",
        "Leasing",
        "Investments",
        "Credit",
        "Holdings",
    ],
}

NAME_SUFFIXES = ["Pvt Ltd", "LLP", "Enterprises", "Industries", "Associates"]

PRODUCTS = {
    "194Q": "Synthetic purchase invoice",
    "194C": "Synthetic contract service",
    "194H": "Synthetic commission ledger",
    "194A": "Synthetic interest ledger",
}


@dataclass(frozen=True)
class Party:
    name: str
    pan: str
    gst: str


@dataclass(frozen=True)
class GeneratedRow:
    section: str
    scenario: str
    row_id: str
    tds_row: dict[str, Any] | None
    ledger_row: dict[str, Any] | None


def allocate_counts(total: int, weights: dict[str, float]) -> dict[str, int]:
    if total <= 0:
        return {key: 0 for key in weights}

    weighted = {key: total * weight for key, weight in weights.items()}
    counts = {key: int(math.floor(value)) for key, value in weighted.items()}
    remaining = total - sum(counts.values())
    order = sorted(
        weights,
        key=lambda key: (weighted[key] - counts[key], weights[key]),
        reverse=True,
    )

    for key in order[:remaining]:
        counts[key] += 1

    if total >= len(weights):
        for key in weights:
            if counts[key] == 0:
                donor = max(counts, key=counts.get)
                counts[donor] -= 1
                counts[key] = 1

    return counts


def make_party(section: str, scenario: str, index: int) -> Party:
    stable = stable_int(section, scenario, index)
    left = NAME_LEFT[stable % len(NAME_LEFT)]
    right = NAME_RIGHT[(stable // 7) % len(NAME_RIGHT)]
    business = NAME_BUSINESS[section][(stable // 13) % len(NAME_BUSINESS[section])]
    suffix = NAME_SUFFIXES[(stable // 17) % len(NAME_SUFFIXES)]
    name = f"{left} {right} {business} {suffix} {index:04d}"
    pan = make_pan(stable)
    gst = make_gst(pan, stable)
    return Party(name=name, pan=pan, gst=gst)


def make_pan(value: int) -> str:
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    first = "".join(letters[(value // (i + 3) + i * 11) % 26] for i in range(5))
    digits = f"{1000 + (value % 9000):04d}"
    last = letters[(value // 19) % 26]
    return f"{first}{digits}{last}"


def make_gst(pan: str, value: int) -> str:
    state_code = f"{1 + (value % 35):02d}"
    checksum = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[value % 36]
    return f"{state_code}{pan}1Z{checksum}"


def stable_int(*parts: Any) -> int:
    joined = "|".join(str(part) for part in parts)
    digest = hashlib.sha256(joined.encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def party_pool_size(dataset_size: str, scenario: str, section_count: int) -> int:
    if scenario == "above_threshold":
        return 2 if dataset_size == "smoke" else 8
    if scenario == "below_threshold":
        return 12 if dataset_size == "smoke" else 80
    if scenario in {"only_in_26q", "only_in_ledger"}:
        return max(8, section_count // 25)
    return max(12, section_count // 18)


def random_fy_date(rng: random.Random) -> date:
    span = (FY_END - FY_START).days
    return FY_START + timedelta(days=rng.randint(0, span))


def shifted_month(value: date) -> date:
    if value.year == 2026 and value.month == 3:
        month = 2
        year = 2026
    elif value.month == 12:
        month = 1
        year = value.year + 1
    else:
        month = value.month + 1
        year = value.year

    last_day = 28
    while True:
        try:
            candidate = date(year, month, last_day + 1)
            last_day += 1
            if candidate.month != month:
                break
        except ValueError:
            break
    return date(year, month, min(value.day, last_day))


def amount_for(section: str, scenario: str, rng: random.Random) -> float:
    if section == "194Q" and scenario == "below_threshold":
        return round(rng.uniform(8_000, 45_000), 2)
    if section == "194Q" and scenario == "above_threshold":
        return round(rng.uniform(650_000, 950_000), 2)
    if section == "194Q":
        return round(rng.uniform(35_000, 275_000), 2)
    if section == "194C":
        return round(rng.uniform(8_000, 180_000), 2)
    if section == "194H":
        return round(rng.uniform(2_500, 85_000), 2)
    return round(rng.uniform(5_000, 240_000), 2)


def tds_for(section: str, amount: float) -> float:
    return round(amount * TDS_RATES[section], 2)


def bill_amount_for(basic_amount: float) -> float:
    return round(basic_amount * 1.18, 2)


def build_tds_row(
    *,
    txn_date: date,
    party: Party,
    amount: float,
    tds: float,
    section: str,
    scenario: str,
    row_id: str,
    pan_override: str | None = None,
) -> dict[str, Any]:
    return {
        "Date / Month": txn_date.isoformat(),
        "Party Name": party.name,
        "PAN Number": party.pan if pan_override is None else pan_override,
        "Amount Paid": amount,
        "TDS Amount": tds,
        "Section": section,
        "Scenario": scenario,
        "Synthetic Row Id": row_id,
    }


def build_ledger_row(
    *,
    txn_date: date,
    party: Party,
    amount: float,
    tds: float,
    section: str,
    scenario: str,
    row_id: str,
    pan_override: str | None = None,
) -> dict[str, Any]:
    pan = party.pan if pan_override is None else pan_override
    common = {
        "Bill No": f"SYN-{section}-{row_id[-8:]}",
        "Party Name": party.name,
        "PAN Number": pan,
        "GST No": make_gst(pan, stable_int(row_id, pan)) if pan else "",
        "TDS Amount": tds,
        "Section": section,
        "Scenario": scenario,
        "Synthetic Row Id": row_id,
        "Description": f"{PRODUCTS[section]} - {scenario.replace('_', ' ')}",
    }

    if section == "194Q":
        return {
            "Bill Date": txn_date.isoformat(),
            **common,
            "Basic Amount": amount,
            "Bill Amount": bill_amount_for(amount),
            "Product Name": PRODUCTS[section],
        }

    return {
        "Date": txn_date.isoformat(),
        **common,
        "Amount": amount,
    }


def generate_rows_for_section(
    *,
    dataset_size: str,
    section: str,
    section_count: int,
    seed: int,
) -> list[GeneratedRow]:
    scenario_weights = (
        SECTION_194Q_SCENARIO_WEIGHTS if section == "194Q" else BASE_SCENARIO_WEIGHTS
    )
    scenario_counts = allocate_counts(section_count, scenario_weights)
    rng = random.Random(seed + stable_int(section) % 1_000_003)
    rows: list[GeneratedRow] = []

    for scenario, count in scenario_counts.items():
        pool_size = party_pool_size(dataset_size, scenario, section_count)
        for index in range(count):
            party = make_party(section, scenario, index % pool_size)
            txn_date = random_fy_date(rng)
            amount = amount_for(section, scenario, rng)
            tds = tds_for(section, amount)
            row_id = f"{dataset_size}-{section}-{scenario}-{index + 1:06d}"

            tds_pan = party.pan
            ledger_pan = party.pan
            ledger_amount = amount
            ledger_tds = tds
            ledger_date = txn_date

            if scenario == "amount_mismatch":
                ledger_amount = round(amount + max(250.0, amount * 0.035), 2)
            elif scenario == "tds_mismatch":
                ledger_tds = round(tds + max(50.0, tds * 0.15), 2)
            elif scenario == "missing_pan":
                tds_pan = ""
                ledger_pan = ""
            elif scenario == "pan_conflict":
                ledger_pan = make_pan(stable_int(party.pan, "conflict"))
            elif scenario == "timing_difference":
                ledger_date = shifted_month(txn_date)

            tds_row = build_tds_row(
                txn_date=txn_date,
                party=party,
                amount=amount,
                tds=tds,
                section=section,
                scenario=scenario,
                row_id=row_id,
                pan_override=tds_pan,
            )

            ledger_row = None
            if scenario != "only_in_26q":
                ledger_row = build_ledger_row(
                    txn_date=ledger_date,
                    party=party,
                    amount=ledger_amount,
                    tds=ledger_tds,
                    section=section,
                    scenario=scenario,
                    row_id=row_id,
                    pan_override=ledger_pan,
                )

            rows.append(
                GeneratedRow(
                    section=section,
                    scenario=scenario,
                    row_id=row_id,
                    tds_row=tds_row,
                    ledger_row=ledger_row,
                )
            )

    only_ledger_count = max(1, round(section_count * ONLY_IN_LEDGER_RATIO))
    pool_size = party_pool_size(dataset_size, "only_in_ledger", section_count)
    for index in range(only_ledger_count):
        scenario = "only_in_ledger"
        party = make_party(section, scenario, index % pool_size)
        txn_date = random_fy_date(rng)
        amount = amount_for(section, scenario, rng)
        tds = tds_for(section, amount)
        row_id = f"{dataset_size}-{section}-{scenario}-{index + 1:06d}"
        rows.append(
            GeneratedRow(
                section=section,
                scenario=scenario,
                row_id=row_id,
                tds_row=None,
                ledger_row=build_ledger_row(
                    txn_date=txn_date,
                    party=party,
                    amount=amount,
                    tds=tds,
                    section=section,
                    scenario=scenario,
                    row_id=row_id,
                ),
            )
        )

    rng.shuffle(rows)
    return rows


def generate_dataset(dataset_size: str, output_root: Path, seed: int) -> Path:
    target_rows = DATASET_SIZES[dataset_size]
    dataset_dir = output_root / dataset_size
    if dataset_dir.exists():
        shutil.rmtree(dataset_dir)
    dataset_dir.mkdir(parents=True, exist_ok=True)

    section_counts = allocate_counts(target_rows, SECTION_WEIGHTS)
    all_rows: list[GeneratedRow] = []
    for section, count in section_counts.items():
        all_rows.extend(
            generate_rows_for_section(
                dataset_size=dataset_size,
                section=section,
                section_count=count,
                seed=seed,
            )
        )

    all_rows.sort(key=lambda row: row.row_id)
    tds_rows = [row.tds_row for row in all_rows if row.tds_row is not None]
    write_xlsx(
        dataset_dir / "26Q.xlsx",
        sheet_name="Deduction",
        headers=TDS_HEADERS,
        rows=tds_rows,
    )

    ledger_files: dict[str, list[tuple[Path, list[dict[str, Any]]]]] = {}
    for section in SECTION_WEIGHTS:
        ledger_rows = [
            row.ledger_row
            for row in all_rows
            if row.section == section and row.ledger_row is not None
        ]
        section_dir = dataset_dir / "ledgers" / section
        section_dir.mkdir(parents=True, exist_ok=True)

        if section == "194C":
            split_count = 3 if dataset_size == "stress" else 2
            split_files = split_rows(ledger_rows, split_count)
            names = [
                "ledger_194C_contractors_main.xlsx",
                "ledger_194C_site_expenses.xlsx",
                "ledger_194C_retention_entries.xlsx",
            ]
        else:
            split_files = [ledger_rows]
            names = [f"ledger_{section}.xlsx" if section != "194Q" else "purchase_194Q.xlsx"]

        ledger_files[section] = []
        headers = PURCHASE_HEADERS if section == "194Q" else GENERIC_LEDGER_HEADERS
        for name, rows in zip(names, split_files):
            path = section_dir / name
            write_xlsx(path, sheet_name="Ledger", headers=headers, rows=rows)
            ledger_files[section].append((path, rows))

    write_readme(
        dataset_dir=dataset_dir,
        dataset_size=dataset_size,
        seed=seed,
        target_rows=target_rows,
        tds_rows=tds_rows,
        ledger_files=ledger_files,
    )
    return dataset_dir


def split_rows(rows: list[dict[str, Any]], split_count: int) -> list[list[dict[str, Any]]]:
    result = [[] for _ in range(split_count)]
    for index, row in enumerate(rows):
        result[index % split_count].append(row)
    return result


def column_name(index: int) -> str:
    name = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        name = chr(65 + remainder) + name
    return name


def write_xlsx(
    path: Path,
    *,
    sheet_name: str,
    headers: list[str],
    rows: list[dict[str, Any]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    shared_strings: dict[str, int] = {}
    shared_values: list[str] = []

    def shared_index(value: Any) -> int:
        text = "" if value is None else str(value)
        existing = shared_strings.get(text)
        if existing is not None:
            return existing
        index = len(shared_values)
        shared_strings[text] = index
        shared_values.append(text)
        return index

    with tempfile.TemporaryDirectory() as tmp:
        sheet_path = Path(tmp) / "sheet1.xml"
        with sheet_path.open("w", encoding="utf-8", newline="") as sheet:
            sheet.write(
                '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                "<sheetData>"
            )
            write_sheet_row(sheet, 1, headers, headers, shared_index)
            for row_number, row in enumerate(rows, start=2):
                write_sheet_row(sheet, row_number, headers, row, shared_index)
            sheet.write("</sheetData></worksheet>")

        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            zip_writestr(
                archive,
                "[Content_Types].xml",
                content_types_xml(),
            )
            zip_writestr(archive, "_rels/.rels", root_rels_xml())
            zip_writestr(archive, "xl/workbook.xml", workbook_xml(sheet_name))
            zip_writestr(archive, "xl/_rels/workbook.xml.rels", workbook_rels_xml())
            zip_write_file(archive, sheet_path, "xl/worksheets/sheet1.xml")
            zip_writestr(archive, "xl/sharedStrings.xml", shared_strings_xml(shared_values))
            zip_writestr(archive, "xl/styles.xml", styles_xml())


def write_sheet_row(
    sheet: Any,
    row_number: int,
    headers: list[str],
    row: list[str] | dict[str, Any],
    shared_index: Any,
) -> None:
    sheet.write(f'<row r="{row_number}">')
    for column_index, header in enumerate(headers, start=1):
        value = row[column_index - 1] if isinstance(row, list) else row.get(header, "")
        ref = f"{column_name(column_index)}{row_number}"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            sheet.write(f'<c r="{ref}"><v>{value}</v></c>')
        else:
            sheet.write(f'<c r="{ref}" t="s"><v>{shared_index(value)}</v></c>')
    sheet.write("</row>")


def zip_writestr(archive: zipfile.ZipFile, name: str, content: str) -> None:
    info = zipfile.ZipInfo(name, FIXED_ZIP_DATE_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o600 << 16
    archive.writestr(info, content.encode("utf-8"))


def zip_write_file(archive: zipfile.ZipFile, source: Path, name: str) -> None:
    info = zipfile.ZipInfo(name, FIXED_ZIP_DATE_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o600 << 16
    archive.writestr(info, source.read_bytes())


def content_types_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        "</Types>"
    )


def root_rels_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        "</Relationships>"
    )


def workbook_xml(sheet_name: str) -> str:
    safe_name = escape(sheet_name[:31])
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        "<sheets>"
        f'<sheet name="{safe_name}" sheetId="1" r:id="rId1"/>'
        "</sheets>"
        "</workbook>"
    )


def workbook_rels_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        "</Relationships>"
    )


def styles_xml() -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '<dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>'
        "</styleSheet>"
    )


def shared_strings_xml(values: list[str]) -> str:
    items = "".join(f"<si><t>{escape(value)}</t></si>" for value in values)
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="{len(values)}" uniqueCount="{len(values)}">'
        f"{items}</sst>"
    )


def write_readme(
    *,
    dataset_dir: Path,
    dataset_size: str,
    seed: int,
    target_rows: int,
    tds_rows: list[dict[str, Any]],
    ledger_files: dict[str, list[tuple[Path, list[dict[str, Any]]]]],
) -> None:
    lines = [
        f"# LedgerMatch Synthetic Dataset: {dataset_size}",
        "",
        "This dataset is fully synthetic and deterministic. It does not use real CA data, real seller names, or real PANs.",
        "",
        f"- Seed: `{seed}`",
        f"- 26Q row target: `{target_rows:,}`",
        f"- Actual 26Q rows: `{len(tds_rows):,}`",
        "- Financial year: `2025-26` (`2025-04-01` to `2026-03-31`)",
        "",
        "## Files",
        "",
        "- `26Q.xlsx` uses sheet `Deduction` and upload-friendly headers: `Date / Month`, `Party Name`, `PAN Number`, `Amount Paid`, `TDS Amount`, `Section`.",
        "- `ledgers/194Q/purchase_194Q.xlsx` uses purchase upload headers: `Bill Date`, `Party Name`, `Basic Amount`, `Bill Amount`.",
        "- `ledgers/194C/` intentionally contains multiple ledger files for same-section mapping and reconciliation tests.",
        "- `ledgers/194H/ledger_194H.xlsx` and `ledgers/194A/ledger_194A.xlsx` use generic ledger headers: `Date`, `Party Name`, `Amount`.",
        "",
        "Every Excel file also includes `Scenario` and `Synthetic Row Id` helper columns so test cases can be located quickly.",
        "",
        "## Scenarios",
        "",
        "| Scenario | Purpose | Where to look |",
        "| --- | --- | --- |",
        "| `exact_match` | Same seller, PAN, date month, amount, and TDS in 26Q and ledger. | 26Q plus all ledger folders |",
        "| `amount_mismatch` | Same seller and PAN, ledger amount differs. | 26Q plus all ledger folders |",
        "| `tds_mismatch` | Same seller and amount, ledger TDS helper column differs. | 26Q plus all ledger folders |",
        "| `only_in_26q` | 26Q row has no ledger counterpart. | `26Q.xlsx` only |",
        "| `only_in_ledger` | Ledger row has no 26Q counterpart. | Ledger folders only |",
        "| `missing_pan` | Seller appears with blank PAN values. | 26Q plus all ledger folders |",
        "| `pan_conflict` | Same seller name has a different ledger PAN. | 26Q plus all ledger folders |",
        "| `timing_difference` | Ledger transaction is shifted to a neighbouring month. | 26Q plus all ledger folders |",
        "| `below_threshold` | 194Q seller totals stay below the threshold band. | `ledgers/194Q/purchase_194Q.xlsx` and 26Q 194Q rows |",
        "| `above_threshold` | 194Q seller totals are intentionally above the threshold band. | `ledgers/194Q/purchase_194Q.xlsx` and 26Q 194Q rows |",
        "",
        "## Row Counts By File",
        "",
        "| File | Rows | Scenarios |",
        "| --- | ---: | --- |",
        f"| `26Q.xlsx` | {len(tds_rows):,} | {scenario_summary(tds_rows)} |",
    ]

    for section in SECTION_WEIGHTS:
        for path, rows in ledger_files[section]:
            rel = path.relative_to(dataset_dir).as_posix()
            lines.append(f"| `{rel}` | {len(rows):,} | {scenario_summary(rows)} |")

    lines.extend(
        [
            "",
            "## Recreate",
            "",
            "```powershell",
            f"python tools/generate_ledger_match_test_datasets.py --size {dataset_size} --seed {seed}",
            "```",
            "",
            "The generator overwrites only the selected dataset folder under `test_datasets/generated/`.",
        ]
    )

    (dataset_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def scenario_summary(rows: list[dict[str, Any]]) -> str:
    counts = Counter(str(row.get("Scenario", "")) for row in rows)
    return ", ".join(f"{scenario}: {count:,}" for scenario, count in sorted(counts.items()))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate deterministic synthetic LedgerMatch Excel datasets."
    )
    parser.add_argument(
        "--size",
        choices=[*DATASET_SIZES.keys(), "all"],
        default="smoke",
        help="Dataset size to generate. Defaults to smoke.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=202526,
        help="Deterministic seed. Defaults to 202526.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test_datasets") / "generated",
        help="Output root. Defaults to test_datasets/generated.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sizes = DATASET_SIZES.keys() if args.size == "all" else [args.size]
    output_root = args.output
    generated: list[Path] = []
    for dataset_size in sizes:
        generated.append(generate_dataset(dataset_size, output_root, args.seed))

    for path in generated:
        print(f"Generated {path}")


if __name__ == "__main__":
    main()
