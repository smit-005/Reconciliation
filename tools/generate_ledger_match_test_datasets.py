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

SUPPORTED_SECTIONS = (
    "194Q",
    "194C",
    "194H",
    "194A",
    "194I_A",
    "194I_B",
    "194J_A",
    "194J_B",
)

DEFAULT_SECTIONS = ("194Q", "194C", "194H", "194A")

SECTION_WEIGHTS = {
    "194Q": 0.35,
    "194C": 0.35,
    "194H": 0.15,
    "194A": 0.15,
    "194I_A": 0.08,
    "194I_B": 0.08,
    "194J_A": 0.08,
    "194J_B": 0.08,
}

TDS_RATES = {
    "194Q": 0.001,
    "194C": 0.01,
    "194H": 0.02,
    "194A": 0.10,
    "194I_A": 0.02,
    "194I_B": 0.10,
    "194J_A": 0.02,
    "194J_B": 0.10,
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
DEFAULT_ALIAS_RATE = 1 / 11
DEFAULT_CROSS_SECTION_SHARED_SELLER_RATE = 1 / 37

PROFILE_SCENARIO_WEIGHTS = {
    "clean_auto": {
        "exact_match": 0.82,
        "amount_mismatch": 0.05,
        "tds_mismatch": 0.04,
        "timing_difference": 0.05,
        "only_in_26q": 0.04,
        "missing_pan": 0.0,
        "pan_conflict": 0.0,
    },
    "export_test": {
        "exact_match": 0.55,
        "amount_mismatch": 0.10,
        "tds_mismatch": 0.10,
        "timing_difference": 0.10,
        "only_in_26q": 0.10,
        "missing_pan": 0.0,
        "pan_conflict": 0.0,
    },
    "manual_mapping_small": {
        "exact_match": 0.35,
        "missing_pan": 0.20,
        "pan_conflict": 0.20,
        "timing_difference": 0.05,
        "only_in_26q": 0.05,
        "amount_mismatch": 0.05,
        "tds_mismatch": 0.05,
    },
    "stress_auto": {
        "exact_match": 0.88,
        "amount_mismatch": 0.03,
        "tds_mismatch": 0.03,
        "timing_difference": 0.03,
        "only_in_26q": 0.03,
        "missing_pan": 0.0,
        "pan_conflict": 0.0,
    },
    "edge_cases_small": {
        "exact_match": 0.35,
        "amount_mismatch": 0.10,
        "tds_mismatch": 0.10,
        "timing_difference": 0.10,
        "only_in_26q": 0.10,
        "missing_pan": 0.10,
        "pan_conflict": 0.10,
    },
}

PROFILE_DEFAULTS = {
    "clean_auto": {
        "only_in_ledger_ratio": 0.02,
        "alias_rate": 0.02,
        "cross_section_shared_seller_rate": 0.01,
        "threshold_rate": 0.05,
    },
    "export_test": {
        "only_in_ledger_ratio": 0.05,
        "alias_rate": 0.04,
        "cross_section_shared_seller_rate": 0.02,
        "threshold_rate": 0.05,
    },
    "manual_mapping_small": {
        "only_in_ledger_ratio": 0.05,
        "alias_rate": 0.18,
        "cross_section_shared_seller_rate": 0.08,
        "threshold_rate": 0.05,
    },
    "stress_auto": {
        "only_in_ledger_ratio": 0.015,
        "alias_rate": 0.01,
        "cross_section_shared_seller_rate": 0.005,
        "threshold_rate": 0.03,
    },
    "edge_cases_small": {
        "only_in_ledger_ratio": 0.05,
        "alias_rate": 0.12,
        "cross_section_shared_seller_rate": 0.05,
        "threshold_rate": 0.05,
    },
}

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
    "194I_A": [
        "Equipment",
        "Plant",
        "Machinery",
        "Fleet",
        "Tools",
        "Rentals",
    ],
    "194I_B": [
        "Properties",
        "Realty",
        "Premises",
        "Warehousing",
        "Facilities",
        "Estates",
    ],
    "194J_A": [
        "Technology",
        "Engineering",
        "Design",
        "Consulting",
        "Analytics",
        "Advisory",
    ],
    "194J_B": [
        "Legal",
        "Audit",
        "Professional",
        "Taxation",
        "Certification",
        "Compliance",
    ],
}

NAME_SUFFIXES = ["Pvt Ltd", "LLP", "Enterprises", "Industries", "Associates"]

PRODUCTS = {
    "194Q": "Synthetic purchase invoice",
    "194C": "Synthetic contract service",
    "194H": "Synthetic commission ledger",
    "194A": "Synthetic interest ledger",
    "194I_A": "Synthetic machinery rent ledger",
    "194I_B": "Synthetic property rent ledger",
    "194J_A": "Synthetic technical service ledger",
    "194J_B": "Synthetic professional service ledger",
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


@dataclass(frozen=True)
class GenerationConfig:
    profile: str | None
    scenario_weights: dict[str, float] | None
    only_in_ledger_ratio: float
    alias_rate: float
    cross_section_shared_seller_rate: float
    threshold_rate: float


def allocate_counts(total: int, weights: dict[str, float]) -> dict[str, int]:
    if total <= 0:
        return {key: 0 for key in weights}

    active_weights = {
        key: value for key, value in weights.items() if value > 0
    }
    if not active_weights:
        return {key: 0 for key in weights}

    weighted = {key: total * weight for key, weight in active_weights.items()}
    counts = {key: 0 for key in weights}
    counts.update({key: int(math.floor(value)) for key, value in weighted.items()})
    remaining = total - sum(counts.values())
    order = sorted(
        active_weights,
        key=lambda key: (weighted[key] - counts[key], weights[key]),
        reverse=True,
    )

    for key in order[:remaining]:
        counts[key] += 1

    if total >= len(active_weights):
        for key in active_weights:
            if counts[key] == 0:
                donor = max(counts, key=counts.get)
                counts[donor] -= 1
                counts[key] = 1

    return counts


def complete_weights(weights: dict[str, float]) -> dict[str, float]:
    result = {key: max(0.0, value) for key, value in weights.items()}
    total = sum(result.values())
    if total <= 0:
        raise ValueError("Scenario weights must contain at least one positive value.")
    if total < 1.0:
        result["exact_match"] = result.get("exact_match", 0.0) + (1.0 - total)
    return result


def scenario_weights_for_section(
    section: str,
    config: GenerationConfig,
) -> dict[str, float]:
    if config.scenario_weights is None:
        return (
            SECTION_194Q_SCENARIO_WEIGHTS
            if section == "194Q"
            else BASE_SCENARIO_WEIGHTS
        )

    weights = complete_weights(config.scenario_weights)
    if section == "194Q" and config.threshold_rate > 0:
        threshold_each = min(
            config.threshold_rate,
            max(0.0, weights.get("exact_match", 0.0) / 3),
        )
        weights["exact_match"] = max(
            0.0,
            weights.get("exact_match", 0.0) - (threshold_each * 2),
        )
        weights["below_threshold"] = threshold_each
        weights["above_threshold"] = threshold_each
    return weights


def rate_hit(value: float, *parts: Any) -> bool:
    if value <= 0:
        return False
    if value >= 1:
        return True
    return stable_int(*parts) / float(0xFFFFFFFFFFFFFFFF) < value


def shared_party_section(
    section: str,
    index: int,
    cross_section_shared_seller_rate: float,
) -> str:
    if rate_hit(cross_section_shared_seller_rate, section, index, "cross-section"):
        return "194C"
    if section in {"194I_A", "194I_B"} and rate_hit(
        cross_section_shared_seller_rate * 2,
        section,
        index,
        "194I-split",
    ):
        return "194I_A"
    if section in {"194J_A", "194J_B"} and rate_hit(
        cross_section_shared_seller_rate * 2,
        section,
        index,
        "194J-split",
    ):
        return "194J_A"
    return section


def make_party(
    section: str,
    scenario: str,
    index: int,
    *,
    cross_section_shared_seller_rate: float,
) -> Party:
    party_section = shared_party_section(
        section,
        index,
        cross_section_shared_seller_rate,
    )
    stable = stable_int(party_section, scenario, index)
    left = NAME_LEFT[stable % len(NAME_LEFT)]
    right = NAME_RIGHT[(stable // 7) % len(NAME_RIGHT)]
    business = NAME_BUSINESS[party_section][
        (stable // 13) % len(NAME_BUSINESS[party_section])
    ]
    suffix = NAME_SUFFIXES[(stable // 17) % len(NAME_SUFFIXES)]
    name = f"{left} {right} {business} {suffix} {index:04d}"
    pan = make_pan(stable)
    gst = make_gst(pan, stable)
    return Party(name=name, pan=pan, gst=gst)


def alias_name(name: str, row_id: str) -> str:
    variants = [
        f"M/s {name}",
        f"{name} Unit",
        f"{name} - Branch",
        name.replace("Pvt Ltd", "Private Limited"),
        name.replace("Enterprises", "Ent."),
    ]
    return variants[stable_int(row_id, "alias") % len(variants)]


def should_use_alias(scenario: str, row_id: str, alias_rate: float) -> bool:
    return scenario in {
        "exact_match",
        "amount_mismatch",
        "tds_mismatch",
        "timing_difference",
    } and rate_hit(alias_rate, row_id, "alias-flag")


def bill_reference(section: str, row_id: str, scenario: str) -> str:
    if scenario in {"exact_match", "timing_difference"} and stable_int(
        row_id, "duplicate-like"
    ) % 29 == 0:
        return f"SYN-{section}-REPEAT-{stable_int(section, row_id) % 17:03d}"
    return f"SYN-{section}-{row_id[-8:]}"


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
    if section == "194I_A":
        return round(rng.uniform(12_000, 160_000), 2)
    if section == "194I_B":
        return round(rng.uniform(18_000, 260_000), 2)
    if section == "194J_A":
        return round(rng.uniform(10_000, 180_000), 2)
    if section == "194J_B":
        return round(rng.uniform(8_000, 220_000), 2)
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
    party_name_override: str | None = None,
) -> dict[str, Any]:
    pan = party.pan if pan_override is None else pan_override
    common = {
        "Bill No": bill_reference(section, row_id, scenario),
        "Party Name": party.name if party_name_override is None else party_name_override,
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
    config: GenerationConfig,
) -> list[GeneratedRow]:
    scenario_weights = scenario_weights_for_section(section, config)
    scenario_counts = allocate_counts(section_count, scenario_weights)
    rng = random.Random(seed + stable_int(section) % 1_000_003)
    rows: list[GeneratedRow] = []

    for scenario, count in scenario_counts.items():
        pool_size = party_pool_size(dataset_size, scenario, section_count)
        for index in range(count):
            party = make_party(
                section,
                scenario,
                index % pool_size,
                cross_section_shared_seller_rate=config.cross_section_shared_seller_rate,
            )
            txn_date = random_fy_date(rng)
            amount = amount_for(section, scenario, rng)
            tds = tds_for(section, amount)
            row_id = f"{dataset_size}-{section}-{scenario}-{index + 1:06d}"

            tds_pan = party.pan
            ledger_pan = party.pan
            ledger_amount = amount
            ledger_tds = tds
            ledger_date = txn_date
            ledger_party_name = party.name

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

            if should_use_alias(scenario, row_id, config.alias_rate):
                ledger_party_name = alias_name(party.name, row_id)

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
                    party_name_override=ledger_party_name,
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

    only_ledger_count = round(section_count * config.only_in_ledger_ratio)
    pool_size = party_pool_size(dataset_size, "only_in_ledger", section_count)
    for index in range(only_ledger_count):
        scenario = "only_in_ledger"
        party = make_party(
            section,
            scenario,
            index % pool_size,
            cross_section_shared_seller_rate=config.cross_section_shared_seller_rate,
        )
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
                    party_name_override=alias_name(party.name, row_id)
                    if should_use_alias(scenario, row_id, config.alias_rate)
                    else None,
                ),
            )
        )

    rng.shuffle(rows)
    return rows


def parse_sections(value: str) -> list[str]:
    sections = [section.strip().upper() for section in value.split(",") if section.strip()]
    if not sections:
        raise argparse.ArgumentTypeError("At least one section must be supplied.")

    invalid = [section for section in sections if section not in SUPPORTED_SECTIONS]
    if invalid:
        allowed = ", ".join(SUPPORTED_SECTIONS)
        raise argparse.ArgumentTypeError(
            f"Unsupported section(s): {', '.join(invalid)}. Supported sections: {allowed}."
        )

    deduped: list[str] = []
    for section in sections:
        if section not in deduped:
            deduped.append(section)
    return deduped


def selected_section_weights(sections: list[str]) -> dict[str, float]:
    total = sum(SECTION_WEIGHTS[section] for section in sections)
    return {section: SECTION_WEIGHTS[section] / total for section in sections}


def build_generation_config(
    *,
    profile: str | None,
    alias_rate: float | None,
    cross_section_shared_seller_rate: float | None,
    only_in_ledger_ratio: float | None,
) -> GenerationConfig:
    profile_defaults = PROFILE_DEFAULTS.get(profile or "", {})
    return GenerationConfig(
        profile=profile,
        scenario_weights=PROFILE_SCENARIO_WEIGHTS.get(profile or ""),
        only_in_ledger_ratio=(
            only_in_ledger_ratio
            if only_in_ledger_ratio is not None
            else float(profile_defaults.get("only_in_ledger_ratio", ONLY_IN_LEDGER_RATIO))
        ),
        alias_rate=(
            alias_rate
            if alias_rate is not None
            else float(profile_defaults.get("alias_rate", DEFAULT_ALIAS_RATE))
        ),
        cross_section_shared_seller_rate=(
            cross_section_shared_seller_rate
            if cross_section_shared_seller_rate is not None
            else float(
                profile_defaults.get(
                    "cross_section_shared_seller_rate",
                    DEFAULT_CROSS_SECTION_SHARED_SELLER_RATE,
                )
            )
        ),
        threshold_rate=float(profile_defaults.get("threshold_rate", 0.10)),
    )


def dataset_folder_name(
    dataset_size: str,
    sections: list[str],
    rows_per_section: int | None,
    profile: str | None,
) -> str:
    profile_prefix = f"{profile}_" if profile else ""
    if rows_per_section is not None:
        if sections == list(SUPPORTED_SECTIONS):
            return f"{profile_prefix}custom_{rows_per_section}_per_section_all_sections"
        if sections == list(DEFAULT_SECTIONS):
            return f"{profile_prefix}custom_{rows_per_section}_per_section"
        return f"{profile_prefix}custom_{rows_per_section}_per_section_{'_'.join(sections)}"

    if sections == list(DEFAULT_SECTIONS):
        return f"{profile_prefix}{dataset_size}"
    if sections == list(SUPPORTED_SECTIONS):
        return f"{profile_prefix}{dataset_size}_all_sections"
    return f"{profile_prefix}{dataset_size}_{'_'.join(sections)}"


def generate_dataset(
    dataset_size: str,
    output_root: Path,
    seed: int,
    *,
    sections: list[str] | None = None,
    rows_per_section: int | None = None,
    config: GenerationConfig | None = None,
) -> Path:
    selected_sections = sections if sections is not None else list(DEFAULT_SECTIONS)
    resolved_config = config or build_generation_config(
        profile=None,
        alias_rate=None,
        cross_section_shared_seller_rate=None,
        only_in_ledger_ratio=None,
    )
    if rows_per_section is not None:
        section_counts = {section: rows_per_section for section in selected_sections}
    else:
        section_counts = allocate_counts(
            DATASET_SIZES[dataset_size],
            selected_section_weights(selected_sections),
        )
    target_rows = sum(section_counts.values())
    dataset_dir = output_root / dataset_folder_name(
        dataset_size,
        selected_sections,
        rows_per_section,
        resolved_config.profile,
    )
    if dataset_dir.exists():
        shutil.rmtree(dataset_dir)
    dataset_dir.mkdir(parents=True, exist_ok=True)

    all_rows: list[GeneratedRow] = []
    for section, count in section_counts.items():
        all_rows.extend(
            generate_rows_for_section(
                dataset_size=dataset_size,
                section=section,
                section_count=count,
                seed=seed,
                config=resolved_config,
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
    for section in selected_sections:
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
        sections=selected_sections,
        rows_per_section=rows_per_section,
        config=resolved_config,
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
    sections: list[str],
    rows_per_section: int | None,
    config: GenerationConfig,
    tds_rows: list[dict[str, Any]],
    ledger_files: dict[str, list[tuple[Path, list[dict[str, Any]]]]],
) -> None:
    command_parts = [
        "python",
        "tools/generate_ledger_match_test_datasets.py",
        "--size",
        dataset_size,
        "--seed",
        str(seed),
        "--sections",
        ",".join(sections),
    ]
    if config.profile is not None:
        command_parts.extend(["--profile", config.profile])
    if rows_per_section is not None:
        command_parts.extend(["--rows-per-section", str(rows_per_section)])
    if config.profile is None or config.alias_rate != float(
        PROFILE_DEFAULTS.get(config.profile, {}).get("alias_rate", DEFAULT_ALIAS_RATE)
    ):
        command_parts.extend(["--alias-rate", f"{config.alias_rate:g}"])
    if config.profile is None or config.cross_section_shared_seller_rate != float(
        PROFILE_DEFAULTS.get(config.profile, {}).get(
            "cross_section_shared_seller_rate",
            DEFAULT_CROSS_SECTION_SHARED_SELLER_RATE,
        )
    ):
        command_parts.extend(
            [
                "--cross-section-shared-seller-rate",
                f"{config.cross_section_shared_seller_rate:g}",
            ]
        )
    if config.profile is None or config.only_in_ledger_ratio != float(
        PROFILE_DEFAULTS.get(config.profile, {}).get(
            "only_in_ledger_ratio",
            ONLY_IN_LEDGER_RATIO,
        )
    ):
        command_parts.extend(["--only-in-ledger-ratio", f"{config.only_in_ledger_ratio:g}"])

    lines = [
        f"# LedgerMatch Synthetic Dataset: {dataset_dir.name}",
        "",
        "This dataset is fully synthetic and deterministic. It does not use real CA data, real seller names, or real PANs.",
        "",
        f"- Seed: `{seed}`",
        f"- Profile: `{config.profile or 'legacy'}`",
        f"- Sections: `{', '.join(sections)}`",
        *(
            [f"- Rows per selected section: `{rows_per_section:,}`"]
            if rows_per_section is not None
            else []
        ),
        f"- Alias variation rate: `{config.alias_rate:g}`",
        f"- Cross-section shared seller rate: `{config.cross_section_shared_seller_rate:g}`",
        f"- Only-in-ledger extra ratio: `{config.only_in_ledger_ratio:g}`",
        f"- 26Q row target: `{target_rows:,}`",
        f"- Actual 26Q rows: `{len(tds_rows):,}`",
        "- Financial year: `2025-26` (`2025-04-01` to `2026-03-31`)",
        "",
        "## Files",
        "",
        "- `26Q.xlsx` uses sheet `Deduction` and upload-friendly headers: `Date / Month`, `Party Name`, `PAN Number`, `Amount Paid`, `TDS Amount`, `Section`.",
    ]

    if "194Q" in sections:
        lines.append(
            "- `ledgers/194Q/purchase_194Q.xlsx` uses purchase upload headers: `Bill Date`, `Party Name`, `Basic Amount`, `Bill Amount`."
        )
    if "194C" in sections:
        lines.append(
            "- `ledgers/194C/` intentionally contains multiple ledger files for same-section mapping and reconciliation tests."
        )
    generic_sections = [section for section in sections if section not in {"194Q", "194C"}]
    if generic_sections:
        generic_files = ", ".join(
            f"`ledgers/{section}/ledger_{section}.xlsx`" for section in generic_sections
        )
        lines.append(
            f"- {generic_files} use generic ledger headers: `Date`, `Party Name`, `Amount`."
        )

    lines.extend(
        [
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
    )

    for section in sections:
        for path, rows in ledger_files[section]:
            rel = path.relative_to(dataset_dir).as_posix()
            lines.append(f"| `{rel}` | {len(rows):,} | {scenario_summary(rows)} |")

    lines.extend(
        [
            "",
            "## Recreate",
            "",
            "```powershell",
            " ".join(command_parts),
            "```",
            "",
            "The generator overwrites only the selected dataset folder under `test_datasets/generated/`.",
        ]
    )

    (dataset_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def scenario_summary(rows: list[dict[str, Any]]) -> str:
    counts = Counter(str(row.get("Scenario", "")) for row in rows)
    return ", ".join(f"{scenario}: {count:,}" for scenario, count in sorted(counts.items()))


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("Value must be greater than zero.")
    return parsed


def ratio(value: str) -> float:
    parsed = float(value)
    if parsed < 0 or parsed > 1:
        raise argparse.ArgumentTypeError("Value must be between 0 and 1.")
    return parsed


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
    parser.add_argument(
        "--rows-per-section",
        type=positive_int,
        help="Generate this many 26Q rows for each selected section instead of using size weights.",
    )
    parser.add_argument(
        "--profile",
        choices=sorted(PROFILE_SCENARIO_WEIGHTS),
        help="Scenario profile for automated, manual, or edge-case datasets.",
    )
    parser.add_argument(
        "--sections",
        type=parse_sections,
        default=list(DEFAULT_SECTIONS),
        help=(
            "Comma-separated sections to generate. Defaults to "
            f"{','.join(DEFAULT_SECTIONS)}. Supported: {','.join(SUPPORTED_SECTIONS)}."
        ),
    )
    parser.add_argument(
        "--alias-rate",
        type=ratio,
        help="Override profile/default alias-name variation rate, from 0 to 1.",
    )
    parser.add_argument(
        "--cross-section-shared-seller-rate",
        type=ratio,
        help="Override profile/default cross-section shared seller rate, from 0 to 1.",
    )
    parser.add_argument(
        "--only-in-ledger-ratio",
        type=ratio,
        help="Override profile/default extra ledger-only row ratio, from 0 to 1.",
    )
    args = parser.parse_args()
    if args.rows_per_section is not None and args.size == "all":
        parser.error("--rows-per-section cannot be combined with --size all.")
    return args


def main() -> None:
    args = parse_args()
    sizes = DATASET_SIZES.keys() if args.size == "all" else [args.size]
    output_root = args.output
    config = build_generation_config(
        profile=args.profile,
        alias_rate=args.alias_rate,
        cross_section_shared_seller_rate=args.cross_section_shared_seller_rate,
        only_in_ledger_ratio=args.only_in_ledger_ratio,
    )
    generated: list[Path] = []
    for dataset_size in sizes:
        generated.append(
            generate_dataset(
                dataset_size,
                output_root,
                args.seed,
                sections=args.sections,
                rows_per_section=args.rows_per_section,
                config=config,
            )
        )

    for path in generated:
        print(f"Generated {path}")


if __name__ == "__main__":
    main()
