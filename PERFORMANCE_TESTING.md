# LedgerMatch Performance Testing

Use the existing synthetic dataset generator:

```powershell
python tools/generate_ledger_match_test_datasets.py
```

Generated Excel files are for local testing only. Do not commit generated Excel files.

## Existing Workflow Test

Run the generated profile export workflow regression/performance smoke:

```powershell
flutter test --no-pub test/features/reconciliation/services/generated_profile_export_workflow_test.dart
```

The test generates a temporary `export_test` dataset with 1,000 rows per section, imports it, runs seller preflight, reconciles all supported sections, exports workbooks, and logs timing metrics.

Look for this line in test output:

```text
LEDGERMATCH_EXPORT_WORKFLOW_METRICS {...}
```

Record:
- `dataset_generation_ms`
- `import_parse_ms`
- `seller_preflight_ms`
- `reconciliation_ms`
- export timings
- `workbook_open_validate_ms`

## Generate 1,000 Rows Per Section

```powershell
python tools/generate_ledger_match_test_datasets.py `
  --profile export_test `
  --rows-per-section 1000 `
  --sections 194Q,194C,194H,194A,194I_A,194I_B,194J_A,194J_B
```

Files are created under:

```text
test_datasets/generated/export_test_custom_1000_per_section_all_sections/
```

## Generate 6,000 Rows Per Section

```powershell
python tools/generate_ledger_match_test_datasets.py `
  --profile stress_auto `
  --rows-per-section 6000 `
  --sections 194Q,194C,194H,194A,194I_A,194I_B,194J_A,194J_B `
  --output test_datasets/generated_perf
```

Files are created under:

```text
test_datasets/generated_perf/stress_auto_custom_6000_per_section_all_sections/
```

This creates 48,000 26Q rows plus ledger/source rows.

## Manual Upload Files

Upload in normal workflow order:

1. `26Q.xlsx`
2. `ledgers/194Q/purchase_194Q.xlsx`
3. `ledgers/194C/ledger_194C_contractors_main.xlsx`
4. `ledgers/194C/ledger_194C_site_expenses.xlsx`
5. `ledgers/194C/ledger_194C_retention_entries.xlsx`
6. `ledgers/194H/ledger_194H.xlsx`
7. `ledgers/194A/ledger_194A.xlsx`
8. `ledgers/194I_A/ledger_194I_A.xlsx`
9. `ledgers/194I_B/ledger_194I_B.xlsx`
10. `ledgers/194J_A/ledger_194J_A.xlsx`
11. `ledgers/194J_B/ledger_194J_B.xlsx`

## Timings To Record

For manual runs, record elapsed time for:

- 26Q upload and mapping confirmation
- each source file upload
- Review All Mappings
- Seller Mapping open/preflight
- Seller Mapping save
- Open Reconciliation
- section switching
- filtering/searching
- Current View export
- Section export
- Pivot/final report export
- detailed report export

## Freeze Symptoms To Note

Write down:

- screen/action where freeze occurs
- dataset size and profile
- section/file being processed
- whether CPU or memory spikes
- whether UI stops repainting
- whether buttons stay disabled after processing
- whether Windows reports the app as not responding
- approximate duration before recovery
- whether retrying the same action reproduces it

## Cleanup

Generated datasets can become large. Keep them local:

```powershell
Remove-Item -LiteralPath test_datasets/generated_perf -Recurse -Force
```

Do not commit generated Excel files or temporary export workbooks.
