# Graph Report - E:\reconciliation_app_codex  (2026-04-19)

## Corpus Check
- 108 files · ~62,220 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 728 nodes · 788 edges · 69 communities detected
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 36 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter/material.dart` - 18 edges
2. `../../core/utils/normalize_utils.dart` - 14 edges
3. `../../models/reconciliation_row.dart` - 9 edges
4. `WriteValue()` - 8 edges
5. `Create()` - 8 edges
6. `OnCreate()` - 7 edges
7. `Destroy()` - 7 edges
8. `../core/utils/date_utils.dart` - 6 edges
9. `../core/utils/parse_utils.dart` - 6 edges
10. `../models/tds_26q_row.dart` - 6 edges

## Surprising Connections (you probably didn't know these)
- `ForceRedraw()` --calls--> `OnCreate()`  [INFERRED]
  E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\flutter_view_controller.cc → E:\reconciliation_app_codex\windows\runner\flutter_window.cpp
- `RegisterPlugins()` --calls--> `OnCreate()`  [INFERRED]
  E:\reconciliation_app_codex\windows\flutter\generated_plugin_registrant.cc → E:\reconciliation_app_codex\windows\runner\flutter_window.cpp
- `ResizeChannel()` --calls--> `GetInstance()`  [INFERRED]
  E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\core_implementations.cc → E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\plugin_registrar.cc
- `SetChannelWarnsOnOverflow()` --calls--> `GetInstance()`  [INFERRED]
  E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\core_implementations.cc → E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\plugin_registrar.cc
- `SetNextFrameCallback()` --calls--> `OnCreate()`  [INFERRED]
  E:\reconciliation_app_codex\windows\flutter\ephemeral\cpp_client_wrapper\flutter_engine.cc → E:\reconciliation_app_codex\windows\runner\flutter_window.cpp

## Communities

### Community 0 - "Community 0"
Cohesion: 0.03
Nodes (64): AlertDialog, BoxDecoration, build, _buildBottomActionBar, _buildHeader, _buildSectionCard, _buildSectionPanel, _buildSectionSelector (+56 more)

### Community 1 - "Community 1"
Cohesion: 0.04
Nodes (51): applyNameMapping, DateTime, extractPanFromSellerKey, _extractYear, GroupingService, looksLikePan, _monthLabelFromDate, normalizeMonthKey (+43 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (54): _activeSummaryCacheKey, _applicableButNo26QAmount, _applicableButNo26QCount, _applicableButNo26QTds, _applyFilters, build, _buildSectionSummaryStrip, _buildSectionTabs (+46 more)

### Community 3 - "Community 3"
Cohesion: 0.04
Nodes (53): addScore, _buildMappedHeaders, buildSampleSignature, _containsDateLikeValues, _containsLargeAmountColumn, _containsPanPattern, _containsSectionValues, _containsTdsAmountColumn (+45 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (35): build, _chip, Container, FileInfoCard, SizedBox, build, Color, Container (+27 more)

### Community 5 - "Community 5"
Cohesion: 0.06
Nodes (34): ../../core/utils/normalize_utils.dart, ../../core/utils/reconciliation_helpers.dart, buildSellerDisplayKey, sortSections, SellerMapping, _extractSectionFromText, _inferSection, _isKnownSection (+26 more)

### Community 6 - "Community 6"
Cohesion: 0.05
Nodes (37): dart:math, _autoMapBestGuess, BoxDecoration, build, _buildColumnCard, _buildColumnsPanel, _buildFileInfoCard, _buildInfoChip (+29 more)

### Community 7 - "Community 7"
Cohesion: 0.09
Nodes (29): SetNextFrameCallback(), OnCreate(), RegisterPlugins(), wWinMain(), ClearPlugins(), GetInstance(), OnRegistrarDestroyed(), PluginRegistrar() (+21 more)

### Community 8 - "Community 8"
Cohesion: 0.06
Nodes (29): buyer_management_screen.dart, buyer_repository.dart, ../data/buyer_store.dart, db_helper.dart, BuyerRepository, BuyerStore, build, BuyerManagementScreen (+21 more)

### Community 9 - "Community 9"
Cohesion: 0.07
Nodes (25): ../core/utils/date_utils.dart, ../core/utils/parse_utils.dart, LedgerUploadFile, NormalizedLedgerRow, NormalizedTransactionRow, PurchaseRow, applyBelowThresholdClassification, buildBaseStatus (+17 more)

### Community 10 - "Community 10"
Cohesion: 0.14
Nodes (20): ResizeChannel(), flutter(), Resize(), DecodeAndProcessResponseEnvelope(), flutter(), DecodeAndProcessResponseEnvelopeInternal(), DecodeMessageInternal(), DecodeMethodCallInternal() (+12 more)

### Community 11 - "Community 11"
Cohesion: 0.08
Nodes (24): dart:typed_data, _cellString, _cellValue, _containsRealTdsSection, DateTime, Exception, _extractSectionCode, _findHeaderRowIndex (+16 more)

### Community 12 - "Community 12"
Cohesion: 0.09
Nodes (22): dart:io, _applyNumberFormat, _autoFitPivot, _autoFitUsefulColumns, _buildExportFileName, ExcelExportService, _getDownloadsPath, getRiskLevel (+14 more)

### Community 13 - "Community 13"
Cohesion: 0.1
Nodes (10): flutter(), Send(), SendResponseData(), SetChannelWarnsOnOverflow(), SetMessageHandler(), flutter(), flutter(), flutter() (+2 more)

### Community 14 - "Community 14"
Cohesion: 0.11
Nodes (16): ../data/db_helper.dart, buyers, DBHelper, import_format_profiles, seller_mappings, build, main, MaterialApp (+8 more)

### Community 15 - "Community 15"
Cohesion: 0.12
Nodes (9): FlutterEngine(), RelinquishEngine(), ReloadSystemFonts(), ShutDown(), FlutterViewController(), ForceRedraw(), HandleTopLevelWindowProc(), FlutterWindow() (+1 more)

### Community 16 - "Community 16"
Cohesion: 0.11
Nodes (15): ImportMappingService, _normalizeCanonicalKey, build, Container, MappingColumnCard, SizedBox, Text, build (+7 more)

### Community 17 - "Community 17"
Cohesion: 0.17
Nodes (11): build, _buildApplicableNo26QSummary, _buildFooterNote, _buildMismatchSummary, _buildTopSummaryCard, Container, _fmt, ReconciliationSummaryPanel (+3 more)

### Community 18 - "Community 18"
Cohesion: 0.2
Nodes (9): _apply194C, _apply194H, _apply194I, _apply194J, _apply194Q, applyRule, _clean, SectionRuleResult (+1 more)

### Community 19 - "Community 19"
Cohesion: 0.25
Nodes (7): AutoMappingResult, AutoMappingService, _isSafeBusinessNameMatch, _levenshteinDistance, _levenshteinSimilarity, normalizePartyName, _similarityScore

### Community 20 - "Community 20"
Cohesion: 0.33
Nodes (5): compareFinancialYearMonthKeys, compareMonthKeys, DateTime, financialYearFromMonthKey, normalizeMonth

### Community 21 - "Community 21"
Cohesion: 0.33
Nodes (5): extractPanFromGstin, looksLikePan, normalizeName, normalizePan, normalizeSection

### Community 22 - "Community 22"
Cohesion: 0.67
Nodes (2): parseDouble, round2

### Community 23 - "Community 23"
Cohesion: 0.67
Nodes (2): copyWith, ReconciliationRow

### Community 24 - "Community 24"
Cohesion: 1.0
Nodes (1): MainActivity

### Community 25 - "Community 25"
Cohesion: 1.0
Nodes (1): Buyer

### Community 26 - "Community 26"
Cohesion: 1.0
Nodes (1): ExcelPreviewData

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): ImportFormatProfile

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): ManualMappingResult

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (1): MappingFieldOption

### Community 30 - "Community 30"
Cohesion: 1.0
Nodes (1): SectionRule

### Community 31 - "Community 31"
Cohesion: 1.0
Nodes (1): TransactionModel

### Community 32 - "Community 32"
Cohesion: 1.0
Nodes (0): 

### Community 33 - "Community 33"
Cohesion: 1.0
Nodes (0): 

### Community 34 - "Community 34"
Cohesion: 1.0
Nodes (0): 

### Community 35 - "Community 35"
Cohesion: 1.0
Nodes (0): 

### Community 36 - "Community 36"
Cohesion: 1.0
Nodes (0): 

### Community 37 - "Community 37"
Cohesion: 1.0
Nodes (0): 

### Community 38 - "Community 38"
Cohesion: 1.0
Nodes (0): 

### Community 39 - "Community 39"
Cohesion: 1.0
Nodes (0): 

### Community 40 - "Community 40"
Cohesion: 1.0
Nodes (0): 

### Community 41 - "Community 41"
Cohesion: 1.0
Nodes (0): 

### Community 42 - "Community 42"
Cohesion: 1.0
Nodes (0): 

### Community 43 - "Community 43"
Cohesion: 1.0
Nodes (0): 

### Community 44 - "Community 44"
Cohesion: 1.0
Nodes (0): 

### Community 45 - "Community 45"
Cohesion: 1.0
Nodes (0): 

### Community 46 - "Community 46"
Cohesion: 1.0
Nodes (0): 

### Community 47 - "Community 47"
Cohesion: 1.0
Nodes (0): 

### Community 48 - "Community 48"
Cohesion: 1.0
Nodes (0): 

### Community 49 - "Community 49"
Cohesion: 1.0
Nodes (0): 

### Community 50 - "Community 50"
Cohesion: 1.0
Nodes (0): 

### Community 51 - "Community 51"
Cohesion: 1.0
Nodes (0): 

### Community 52 - "Community 52"
Cohesion: 1.0
Nodes (0): 

### Community 53 - "Community 53"
Cohesion: 1.0
Nodes (0): 

### Community 54 - "Community 54"
Cohesion: 1.0
Nodes (0): 

### Community 55 - "Community 55"
Cohesion: 1.0
Nodes (0): 

### Community 56 - "Community 56"
Cohesion: 1.0
Nodes (0): 

### Community 57 - "Community 57"
Cohesion: 1.0
Nodes (0): 

### Community 58 - "Community 58"
Cohesion: 1.0
Nodes (0): 

### Community 59 - "Community 59"
Cohesion: 1.0
Nodes (0): 

### Community 60 - "Community 60"
Cohesion: 1.0
Nodes (0): 

### Community 61 - "Community 61"
Cohesion: 1.0
Nodes (0): 

### Community 62 - "Community 62"
Cohesion: 1.0
Nodes (0): 

### Community 63 - "Community 63"
Cohesion: 1.0
Nodes (0): 

### Community 64 - "Community 64"
Cohesion: 1.0
Nodes (0): 

### Community 65 - "Community 65"
Cohesion: 1.0
Nodes (0): 

### Community 66 - "Community 66"
Cohesion: 1.0
Nodes (0): 

### Community 67 - "Community 67"
Cohesion: 1.0
Nodes (0): 

### Community 68 - "Community 68"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **475 isolated node(s):** `MainActivity`, `MyApp`, `main`, `build`, `MaterialApp` (+470 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 24`** (2 nodes): `MainActivity.kt`, `MainActivity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 25`** (2 nodes): `buyer.dart`, `Buyer`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 26`** (2 nodes): `excel_preview_data.dart`, `ExcelPreviewData`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 27`** (2 nodes): `import_format_profile.dart`, `ImportFormatProfile`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (2 nodes): `manual_mapping_result.dart`, `ManualMappingResult`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (2 nodes): `mapping_field_option.dart`, `MappingFieldOption`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 30`** (2 nodes): `section_rule.dart`, `SectionRule`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 31`** (2 nodes): `transaction.dart`, `TransactionModel`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 32`** (2 nodes): `flutter()`, `binary_messenger_impl.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 33`** (2 nodes): `flutter()`, `byte_buffer_streams.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 34`** (2 nodes): `texture_registrar_impl.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 35`** (2 nodes): `flutter()`, `binary_messenger.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 36`** (2 nodes): `flutter()`, `byte_streams.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 37`** (2 nodes): `GpuPreference()`, `dart_project.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 38`** (2 nodes): `encodable_value.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 39`** (2 nodes): `event_sink.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 40`** (2 nodes): `event_stream_handler.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 41`** (2 nodes): `event_stream_handler_functions.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 42`** (2 nodes): `flutter_engine.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 43`** (2 nodes): `flutter_view.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 44`** (2 nodes): `flutter_view_controller.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 45`** (2 nodes): `method_call.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 46`** (2 nodes): `method_result.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 47`** (2 nodes): `method_result_functions.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 48`** (2 nodes): `plugin_registrar.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 49`** (2 nodes): `plugin_registrar_windows.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 50`** (2 nodes): `plugin_registry.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 51`** (2 nodes): `standard_codec_serializer.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 52`** (2 nodes): `standard_message_codec.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 53`** (2 nodes): `standard_method_codec.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 54`** (2 nodes): `texture_registrar.h`, `flutter()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 55`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 56`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 57`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 58`** (1 nodes): `reconciliation_summary.dart`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 59`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 60`** (1 nodes): `flutter_export.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 61`** (1 nodes): `flutter_messenger.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 62`** (1 nodes): `flutter_plugin_registrar.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 63`** (1 nodes): `flutter_texture_registrar.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 64`** (1 nodes): `flutter_windows.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 65`** (1 nodes): `engine_method_result.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 66`** (1 nodes): `resource.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 67`** (1 nodes): `utils.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 68`** (1 nodes): `win32_window.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter/material.dart` connect `Community 4` to `Community 0`, `Community 2`, `Community 5`, `Community 6`, `Community 8`, `Community 14`, `Community 16`, `Community 17`?**
  _High betweenness centrality (0.190) - this node is a cross-community bridge._
- **Why does `../../models/reconciliation_row.dart` connect `Community 5` to `Community 1`, `Community 2`, `Community 3`, `Community 9`, `Community 12`?**
  _High betweenness centrality (0.108) - this node is a cross-community bridge._
- **Why does `../../core/utils/normalize_utils.dart` connect `Community 5` to `Community 1`, `Community 2`, `Community 3`, `Community 6`, `Community 9`, `Community 14`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Create()` (e.g. with `wWinMain()` and `GetInstance()`) actually correct?**
  _`Create()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `MainActivity`, `MyApp`, `main` to the rest of the system?**
  _475 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.03 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._