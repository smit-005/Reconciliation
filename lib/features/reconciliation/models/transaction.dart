class TransactionModel {
  final String date;
  final String month;
  final String sellerName;
  final double baseAmount;
  final double deductedAmount;
  final double tdsAmount;

  TransactionModel({
    required this.date,
    required this.month,
    required this.sellerName,
    required this.baseAmount,
    required this.deductedAmount,
    required this.tdsAmount,
  });

  factory TransactionModel.fromRow(List<dynamic> row) {
    return TransactionModel(
      date: row.isNotEmpty ? row[0].toString() : '',
      month: row.length > 1 ? row[1].toString() : '',
      sellerName: row.length > 2 ? row[2].toString() : '',
      baseAmount: row.length > 3
          ? double.tryParse(row[3].toString()) ?? 0
          : 0,
      deductedAmount: row.length > 4
          ? double.tryParse(row[4].toString()) ?? 0
          : 0,
      tdsAmount: row.length > 5
          ? double.tryParse(row[5].toString()) ?? 0
          : 0,
    );
  }
}
