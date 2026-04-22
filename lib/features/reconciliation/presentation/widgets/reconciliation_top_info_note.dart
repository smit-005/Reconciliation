import 'package:flutter/material.dart';

class ReconciliationTopInfoNote extends StatelessWidget {
  const ReconciliationTopInfoNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: const Text(
        'Relevant sellers only: this report includes only sellers who are present in 26Q or whose total purchase crosses \u00e2\u201a\u00b950,00,000 in the financial year. Sellers below threshold and not present in 26Q are excluded to avoid false mismatches.',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

