import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emf_sat_tracker/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EMFSatTrackerApp());

    // Verify that the app title is present
    expect(find.text('EMF Satellite Tracker'), findsOneWidget);

    // Verify the track button exists
    expect(find.text('Track Satellites'), findsOneWidget);
  });
}