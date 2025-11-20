import 'package:flutter/services.dart';

class WidgetService {
  static const platform = MethodChannel('com.ziehro.satwatcher/widget');

  static Future<void> updateWidget({
    required double emfValue,
    required int satCount,
    required double percentLimit,
    required String nextPass,
  }) async {
    try {
      // Keys are now snake_case to match SharedPreferences/Kotlin consistency
      await platform.invokeMethod('updateWidget', {
        'emf_value': emfValue,
        'sat_count': satCount,
        'percent_limit': percentLimit,
        'next_pass': nextPass,
      });
    } on PlatformException catch (e) {
      // Use specific PlatformException handling for robustness
      print("Failed to update widget: '${e.message}'.");
    }
  }
}