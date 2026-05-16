import 'package:flutter/foundation.dart';

class AppLogger {
  static const bool verboseEnabled = bool.fromEnvironment(
    'LEDGERMATCH_VERBOSE_LOGS',
    defaultValue: false,
  );

  static void debug(String message, {int? wrapWidth}) {
    if (!verboseEnabled) return;
    debugPrint(message, wrapWidth: wrapWidth);
  }

  static void warning(String message, {int? wrapWidth}) {
    debugPrint(message, wrapWidth: wrapWidth);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    int? wrapWidth,
  }) {
    debugPrint(message, wrapWidth: wrapWidth);
    if (error != null) {
      debugPrint('Error: $error', wrapWidth: wrapWidth);
    }
    if (stackTrace != null) {
      debugPrint('$stackTrace', wrapWidth: wrapWidth);
    }
  }
}
