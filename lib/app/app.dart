import 'package:flutter/material.dart';

import 'package:reconciliation_app/app/routes.dart';
import 'package:reconciliation_app/core/theme/app_theme.dart';

class ReconciliationApp extends StatelessWidget {
  const ReconciliationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TDS Reconciliation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
