import 'package:flutter/material.dart';

import 'package:reconciliation_app/app/routes.dart';

class ReconciliationApp extends StatelessWidget {
  const ReconciliationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TDS Reconciliation',
      debugShowCheckedModeBanner: false,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
