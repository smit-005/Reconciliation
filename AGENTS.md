# LedgerMatch Engineering Rules

## Project Overview

LedgerMatch is a Flutter Windows desktop application for TDS reconciliation and audit workflows used by CA offices.

Primary workflow:
Upload 26Q -> Review Mapping -> Upload Ledger -> Seller Mapping -> Reconciliation -> Pivot Export

Architecture goals:

- Stable desktop-first workflow
- Large dataset handling
- Section-aware reconciliation
- Reusable centralized UI
- Real-world messy ledger support

---

# Architecture Rules

## Core Architecture

- Feature-based Flutter architecture
- Shared reusable widgets under `lib/core/widgets`
- SQLite storage via `sqflite_common_ffi`
- Reconciliation logic must remain section-aware
- Avoid business logic inside widgets/screens where possible

## Centralized UI

Prefer shared UI components:

- AppSectionCard
- AppMetricCard
- AppCompactMetricCard
- AppStatusBadge
- AppPrimaryButton
- AppSecondaryButton
- AppFilterBar
- AppStickyActionBar

Reconciliation screen visual language is the UI source of truth.

Do not create duplicate styling systems unless necessary.

---

# Core Workflow Rules

Official workflow:

1. Upload 26Q
2. Review 26Q Mapping
3. Upload Ledger / Source Files
4. Seller Mapping Review
5. Open Reconciliation
6. Export Pivot / Reports

Do not bypass workflow gating unless explicitly intended.

---

# Seller Mapping Rules

## Mapping Semantics

- Left side shows ONLY 26Q sellers
- Right side shows ONLY ledger candidates
- Suggestions are display-only until explicitly accepted
- Clearing mapping must not auto-remap seller
- Same-section matching only
- Cross-section PAN/name conflict leakage forbidden

## Status Rules

Primary statuses:

- Unmapped
- 26Q Unmatched
- PAN Conflict
- Mapped
- Mapped (PAN missing)
- Linked to Ledger
- Timing Difference
- Missing in Books
- Marked Separate

## Candidate Rules

Right-side candidates should prioritize:

1. Existing mapped seller
2. Strong suggestions
3. Same-section candidates
4. Search matches

Do not show unrelated 26Q sellers in candidate panel.

## Persistence Rules

- Saved mappings must hydrate correctly after reopen
- `__LINK_LEDGER__:<rowKey>` linkage must remain stable
- Cleared rows must remain unmapped until explicit action

---

# Reconciliation Rules

## Section Awareness

All reconciliation operations must remain section-aware.

Grouping keys should include:

- Seller identity
- Financial year
- Section
- Month

Do not allow section leakage.

## Threshold Logic

194Q threshold logic must remain enforced:

- Below-threshold sellers should not appear in Summary views
- Threshold handling must remain deterministic

## Exception Handling

Timing Difference and Missing in Books are review exceptions, not auto-resolved mappings.

---

# Upload & Column Mapping Rules

## Required Mapping

For 194Q purchases:
Required:

- Party Name
- Bill Date or EOM
- Bill Amount or Basic Amount

Optional:

- PAN
- GST

Bill No must not be treated as mandatory.

## Parsing Rules

- Avoid synchronous heavy parsing on UI thread
- Prefer deferred processing for large files
- Preview generation should remain lightweight
- Header detection should reject decorative rows

---

# Performance Rules

## UI Performance

- Avoid full rebuilds
- Avoid unnecessary recomputation
- Use caching where possible
- Avoid blocking UI thread

## Data Handling

Target dataset handling:

- 60k–75k rows
- Large Excel ledgers
- Multi-section reconciliation

Heavy operations should use:

- caching
- isolates/compute()
- compacted preflight analysis

---

# Export Rules

## Workspace Structure

Preferred structure:

Buyer/
└── FinancialYear/
├── Working/
├── Source_Files/
└── Exports/

## Export Behavior

- Pivot export should support:
  - Current section export
  - All sections export
  - Combined workbook export
- Export paths should remain deterministic
- Fallback export handling must remain safe

---

# Testing & Safety Rules

Before major changes:

- Test full workflow end-to-end
- Test seller mapping persistence
- Test section isolation
- Test export correctness
- Test reopen/reload behavior

Avoid risky refactors before demos or CA office validation.

---

# Demo Philosophy

Current priority:

- Stability
- Trustworthiness
- Real workflow validation

Not priority:

- Massive feature expansion
- Architecture rewrites
- Premature optimization

Real CA office feedback is more important than speculative features.

---

# Graphify

This project has a Graphify knowledge graph at:

graphify-out/

Rules:

- Before answering architecture or codebase questions, read:
  - `graphify-out/GRAPH_REPORT.md`
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw files
- After modifying code files:
  - Run:
    `graphify update .`
  - Keep graph current using AST-only updates

## Graphify Usage

Use Graphify for:

- god-node detection
- duplicate-code analysis
- architecture review
- dependency visualization
- community/module structure analysis

---

# Git Rules

Before pushing:

- Do not commit temp/debug files
- Do not commit large export datasets
- Keep `.gitignore` clean
- Use milestone tags for stable demo builds

Recommended milestone tags:

- v0.9-demo-ready
- v1.0-ca-validation
- v1.1-stability
