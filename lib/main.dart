import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await NotificationService.init();
  runApp(const EMFSatTrackerApp());
}

class EMFSatTrackerApp extends StatelessWidget {
  const EMFSatTrackerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EMF Satellite Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SatelliteTrackerHome(),
    );
  }
}