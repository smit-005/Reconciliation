import 'package:flutter/material.dart';

import 'package:reconciliation_app/features/home/presentation/screens/home_screen.dart';
import 'package:reconciliation_app/features/settings/presentation/screens/settings_screen.dart';

class AppRoutes {
  static const home = '/';
  static const settings = '/settings';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case AppRoutes.settings:
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
    }
  }
}
