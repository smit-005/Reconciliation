import '../models/mapping_field_option.dart';

class ImportMappingService {
  static const String purchaseFileType = 'purchase';
  static const String tds26qFileType = 'tds26q';
  static const String genericLedgerFileType = 'genericLedger';

  static List<MappingFieldOption> fieldOptionsFor(String fileType) {
    if (fileType == genericLedgerFileType) {
      return const [
        MappingFieldOption(
          key: 'date',
          label: 'Date',
          description: 'Transaction or voucher date',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'party_name',
          label: 'Party Name',
          description: 'Ledger or vendor name',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'amount',
          label: 'Amount',
          description: 'Gross, taxable, or ledger amount',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'bill_no',
          label: 'Bill No',
          description: 'Invoice, voucher, or reference number',
        ),
        MappingFieldOption(
          key: 'pan_number',
          label: 'PAN Number',
          description: 'Vendor PAN',
        ),
        MappingFieldOption(
          key: 'gst_no',
          label: 'GST No',
          description: 'Vendor GSTIN',
        ),
        MappingFieldOption(
          key: 'description',
          label: 'Description',
          description: 'Narration or particulars',
        ),
      ];
    }

    if (fileType == tds26qFileType) {
      return const [
        MappingFieldOption(
          key: 'date_month',
          label: 'Date / Month',
          description: 'Payment or credit month column',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'party_name',
          label: 'Party Name',
          description: 'Deductee or seller name',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'pan_number',
          label: 'PAN Number',
          description: 'Deductee PAN',
          importantField: true,
        ),
        MappingFieldOption(
          key: 'amount_paid',
          label: 'Amount Paid',
          description: 'Amount paid or credited',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'tds_amount',
          label: 'TDS Amount',
          description: 'Tax deducted amount',
          requiredField: true,
          importantField: true,
        ),
        MappingFieldOption(
          key: 'section',
          label: 'Section',
          description: 'TDS section code',
          requiredField: true,
          importantField: true,
        ),
      ];
    }

    return const [
      MappingFieldOption(
        key: 'date',
        label: 'Bill Date',
        description: 'Invoice or voucher date',
        requiredField: true,
        importantField: true,
      ),
      MappingFieldOption(
        key: 'eom',
        label: 'EOM',
        description: 'Month-end date when bill date is unavailable',
        importantField: true,
      ),
      MappingFieldOption(
        key: 'bill_no',
        label: 'Bill No',
        description: 'Invoice or voucher number',
        requiredField: true,
        importantField: true,
      ),
      MappingFieldOption(
        key: 'party_name',
        label: 'Party Name',
        description: 'Seller or vendor name',
        requiredField: true,
        importantField: true,
      ),
      MappingFieldOption(
        key: 'basic_amount',
        label: 'Basic Amount',
        description: 'Product or taxable amount',
        importantField: true,
      ),
      MappingFieldOption(
        key: 'bill_amount',
        label: 'Bill Amount',
        description: 'Gross or total bill amount',
        requiredField: true,
        importantField: true,
      ),
      MappingFieldOption(
        key: 'gst_no',
        label: 'GST No',
        description: 'GSTIN of seller',
      ),
      MappingFieldOption(
        key: 'pan_number',
        label: 'PAN Number',
        description: 'Seller PAN',
      ),
      MappingFieldOption(
        key: 'productname',
        label: 'Product Name',
        description: 'Item or description column',
      ),
    ];
  }

  static List<MappingFieldOption> requiredFieldsFor(String fileType) {
    if (fileType == genericLedgerFileType) {
      return const [
        MappingFieldOption(
          key: 'date',
          label: 'Date',
          description: 'Required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'party_name',
          label: 'Party Name',
          description: 'Required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'amount',
          label: 'Amount',
          description: 'Required',
          requiredField: true,
        ),
      ];
    }

    if (fileType == tds26qFileType) {
      return const [
        MappingFieldOption(
          key: 'date_month',
          label: 'Date / Month',
          description: 'Required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'party_or_pan',
          label: 'Party Name or PAN',
          description: 'At least one is required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'amount_paid',
          label: 'Amount Paid',
          description: 'Required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'tds_amount',
          label: 'TDS Amount',
          description: 'Required',
          requiredField: true,
        ),
        MappingFieldOption(
          key: 'section',
          label: 'Section',
          description: 'Required',
          requiredField: true,
        ),
      ];
    }

    return const [
      MappingFieldOption(
        key: 'date_or_eom',
        label: 'Bill Date or EOM',
        description: 'At least one is required',
        requiredField: true,
      ),
      MappingFieldOption(
        key: 'party_name',
        label: 'Party Name',
        description: 'Required',
        requiredField: true,
      ),
      MappingFieldOption(
        key: 'bill_no',
        label: 'Bill No',
        description: 'Required',
        requiredField: true,
      ),
      MappingFieldOption(
        key: 'amount_column',
        label: 'Amount Column',
        description: 'Map Bill Amount or Basic Amount',
        requiredField: true,
      ),
    ];
  }

  static Map<String, String> buildCanonicalMapping(
    Map<String, String> rawToCanonical,
  ) {
    final canonical = <String, String>{};

    for (final entry in rawToCanonical.entries) {
      final rawKey = entry.key.trim();
      final canonicalKey = _normalizeCanonicalKey(entry.value.trim());
      if (rawKey.isEmpty || canonicalKey.isEmpty) continue;
      canonical[canonicalKey] = rawKey;
    }

    return canonical;
  }

  static String _normalizeCanonicalKey(String key) {
    switch (key) {
      case 'pan_no':
        return 'pan_number';
      case 'tds':
        return 'tds_amount';
      case 'deducted_amount':
        return 'amount_paid';
      default:
        return key;
    }
  }

  static List<String> validateSelections({
    required String fileType,
    required Map<String, String> rawToCanonical,
  }) {
    final errors = <String>[];
    final canonicalMapping = buildCanonicalMapping(rawToCanonical);
    if (fileType == purchaseFileType &&
        !canonicalMapping.containsKey('date') &&
        !canonicalMapping.containsKey('eom')) {
      errors.add('Map either Bill Date or EOM');
    }

    if (fileType == purchaseFileType &&
        !canonicalMapping.containsKey('party_name')) {
      errors.add('Party Name is required');
    }

    if (fileType == purchaseFileType &&
        !canonicalMapping.containsKey('bill_no')) {
      errors.add('Bill No is required');
    }

    if (fileType == purchaseFileType &&
        !canonicalMapping.containsKey('bill_amount') &&
        !canonicalMapping.containsKey('basic_amount')) {
      errors.add('Map either Bill Amount or Basic Amount');
    }

    if (fileType == tds26qFileType &&
        !canonicalMapping.containsKey('date_month')) {
      errors.add('Date / Month is required');
    }

    if (fileType == tds26qFileType &&
        !canonicalMapping.containsKey('party_name') &&
        !canonicalMapping.containsKey('pan_number')) {
      errors.add('Map either Party Name or PAN Number');
    }

    if (fileType == tds26qFileType &&
        !canonicalMapping.containsKey('amount_paid')) {
      errors.add('Amount Paid is required');
    }

    if (fileType == tds26qFileType &&
        !canonicalMapping.containsKey('tds_amount')) {
      errors.add('TDS Amount is required');
    }

    if (fileType == tds26qFileType &&
        !canonicalMapping.containsKey('section')) {
      errors.add('Section is required');
    }

    if (fileType == genericLedgerFileType &&
        !canonicalMapping.containsKey('date')) {
      errors.add('Date is required');
    }

    if (fileType == genericLedgerFileType &&
        !canonicalMapping.containsKey('party_name')) {
      errors.add('Party Name is required');
    }

    if (fileType == genericLedgerFileType &&
        !canonicalMapping.containsKey('amount')) {
      errors.add('Amount is required');
    }

    return errors;
  }
}
