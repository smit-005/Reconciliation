import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/excel_service.dart';
import '../services/reconciliation_service.dart';
import '../models/purchase_row.dart';
import '../models/tds_26q_row.dart';
import 'reconciliation_screen.dart';
import '../services/tds_26q_parser.dart';

class ExcelUploadScreen extends StatefulWidget {
  final String selectedBuyerId;
  final String selectedBuyerName;
  final String selectedBuyerPan;

  const ExcelUploadScreen({
    super.key,
    required this.selectedBuyerId,
    required this.selectedBuyerName,
    required this.selectedBuyerPan,
  });

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  bool isLoadingPurchase = false;
  bool isLoadingTds = false;

  String? purchaseFileName;
  String? tdsFileName;

  List<PurchaseRow> purchaseRows = [];
  List<Tds26QRow> tdsRows = [];

  String? detectedGstNo;

  Future<void> uploadPurchaseRegister() async {
    setState(() {
      isLoadingPurchase = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          isLoadingPurchase = false;
        });
        return;
      }

      final pickedFile = result.files.single;

      if (pickedFile.bytes == null) {
        setState(() {
          isLoadingPurchase = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read purchase file bytes')),
          );
        }
        return;
      }

      final bytes = pickedFile.bytes!;

      if (!ExcelService.isPurchaseRegisterFormat(bytes)) {
        setState(() {
          isLoadingPurchase = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid purchase register format')),
          );
        }
        return;
      }

      final parsedPurchaseRows = ExcelService.parsePurchaseRows(bytes);
      final gstNo = ExcelService.detectGstNoFromPurchase(parsedPurchaseRows);

      debugPrint('Purchase rows count: ${parsedPurchaseRows.length}');
      if (parsedPurchaseRows.isNotEmpty) {
        debugPrint('First purchase party: ${parsedPurchaseRows.first.partyName}');
      }

      setState(() {
        purchaseFileName = pickedFile.name;
        purchaseRows = parsedPurchaseRows;
        detectedGstNo = gstNo;
        isLoadingPurchase = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Purchase register uploaded: ${purchaseRows.length} rows',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        isLoadingPurchase = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase upload error: $e')),
        );
      }
    }
  }

  Future<void> uploadTds26QFile() async {
    setState(() {
      isLoadingTds = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => isLoadingTds = false);
        return;
      }

      final pickedFile = result.files.single;

      if (pickedFile.bytes == null) {
        setState(() => isLoadingTds = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read 26Q file')),
        );
        return;
      }

      final bytes = pickedFile.bytes!;

      // ✅ NEW PARSER
      final parserResult = Tds26QParser.parseBytes(bytes);
      final rawRows = parserResult.rows;

      final parsedTdsRows = rawRows.map((e) {
        return Tds26QRow.fromMap({
          'month': e.monthLabel,
          'financial_year': e.fyLabel,
          'deductee_name': e.partyName,
          'pan': e.pan,
          'amount': e.amountPaidCredited,
          'tds': e.totalTaxDeducted,
          'section': e.section,
          'nature_of_payment': e.rawNatureOfPayment,
        });
      }).toList();

      setState(() {
        tdsFileName = pickedFile.name;
        tdsRows = parsedTdsRows;
        isLoadingTds = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('26Q uploaded: ${tdsRows.length} rows')),
      );
    } catch (e) {
      setState(() => isLoadingTds = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('26Q upload error: $e')),
      );
    }
  }

  void openReconciliationScreen() {
    if (purchaseRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload purchase register first')),
      );
      return;
    }

    if (tdsRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload 26Q file first')),
      );
      return;
    }

    debugPrint('Opening reconciliation...');
    debugPrint('Purchase rows passed: ${purchaseRows.length}');
    debugPrint('TDS rows passed: ${tdsRows.length}');
    debugPrint('Selected buyer: ${widget.selectedBuyerName}');
    debugPrint('Selected buyer PAN: ${widget.selectedBuyerPan}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReconciliationScreen(
          purchaseRows: purchaseRows,
          tdsRows: tdsRows,
          buyerName: widget.selectedBuyerName,
          buyerPan: widget.selectedBuyerPan,
          gstNo: detectedGstNo ?? '',
        ),
      ),
    );
  }

  Widget buildInfoCard({
    required String title,
    required String? fileName,
    required bool isUploaded,
    required bool isLoading,
    required VoidCallback onUpload,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                fileName ?? 'No file selected',
                style: TextStyle(
                  fontSize: 14,
                  color: fileName == null ? Colors.grey.shade600 : Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: isLoading ? null : onUpload,
                  child: Text(isLoading ? 'Loading...' : 'Upload'),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isUploaded
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isUploaded ? 'Uploaded' : 'Pending',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isUploaded
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSummaryBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _summaryTile('Buyer Name', widget.selectedBuyerName),
          _summaryTile('Buyer PAN', widget.selectedBuyerPan),
          _summaryTile('GST No', detectedGstNo ?? '-'),
          _summaryTile('Purchase Rows', purchaseRows.length.toString()),
          _summaryTile('26Q Rows', tdsRows.length.toString()),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildInstructionBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: const Text(
        'Step 1: Select buyer from home screen.\n'
            'Step 2: Upload purchase register Excel.\n'
            'Step 3: Upload 26Q / TDS Excel.\n'
            'Step 4: Open reconciliation to see month-wise calculation and difference.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchaseUploaded = purchaseRows.isNotEmpty;
    final tdsUploaded = tdsRows.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Excel Upload'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            buildInstructionBox(),
            const SizedBox(height: 16),
            Row(
              children: [
                buildInfoCard(
                  title: 'Purchase Register',
                  fileName: purchaseFileName,
                  isUploaded: purchaseUploaded,
                  isLoading: isLoadingPurchase,
                  onUpload: uploadPurchaseRegister,
                ),
                const SizedBox(width: 16),
                buildInfoCard(
                  title: '26Q / TDS File',
                  fileName: tdsFileName,
                  isUploaded: tdsUploaded,
                  isLoading: isLoadingTds,
                  onUpload: uploadTds26QFile,
                ),
              ],
            ),
            const SizedBox(height: 16),
            buildSummaryBox(),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ready for Reconciliation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      purchaseUploaded && tdsUploaded
                          ? 'Both files uploaded successfully. You can now open the reconciliation screen.'
                          : 'Please upload both files to continue.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (purchaseUploaded && tdsUploaded)
                            ? openReconciliationScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          'Open Reconciliation',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}