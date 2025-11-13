import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:sgp4_sdp4/sgp4_sdp4.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class SatelliteTrackerHome extends StatefulWidget {
  const SatelliteTrackerHome({Key? key}) : super(key: key);

  @override
  State<SatelliteTrackerHome> createState() => _SatelliteTrackerHomeState();
}

class _SatelliteTrackerHomeState extends State<SatelliteTrackerHome>
    with TickerProviderStateMixin {
  Position? _currentPosition;
  List<SatellitePass> _passes = [];
  bool _isLoading = false;
  String _statusMessage = 'Tap to start tracking';
  double _powerThreshold = 1.0;
  Set<String> _selectedTypes = {'ALL'};
  Timer? _updateTimer;
  late AnimationController _radarController;
  late AnimationController _pulseController;

  final Map<String, double> _satellitePower = {
    'RADAR': 5.0, // SAR satellites - very high power
    'GPS-OPS': 3.0, // GPS - medium-high power
    'GALILEO': 3.0,
    'BEIDOU': 3.0,
    'GLONASS-OPS': 3.0,
    'TDRSS': 4.5, // Very high power relay
    'SARSAT': 2.5,
    'GOES': 3.5, // Weather radar
    'MUSSON': 3.5,
  };

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadPreferences();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _radarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _powerThreshold = prefs.getDouble('powerThreshold') ?? 1.0;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('powerThreshold', _powerThreshold);
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage = 'Location services disabled';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage = 'Location permission denied';
          });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _statusMessage =
        'Location: ${position.latitude.toStringAsFixed(4)}°, ${position.longitude.toStringAsFixed(4)}°';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error getting location: $e';
      });
    }
  }

  Future<void> _loadSatellites() async {
    if (_currentPosition == null) {
      await _getCurrentLocation();
      if (_currentPosition == null) return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading satellites...';
    });

    try {
      final categories = [
        'radar',
        'gps-ops',
        'galileo',
        'beidou',
        'glonass-ops',
        'tdrss',
        'sarsat',
        'goes',
        'musson'
      ];

      List<SatelliteData> allSatellites = [];
      for (var category in categories) {
        final sats = await _fetchTLEs(category);
        allSatellites.addAll(sats);
      }

      final passes = _calculatePasses(allSatellites);
      setState(() {
        _passes = passes;
        _isLoading = false;
        _statusMessage = 'Found ${passes.length} passes';
      });

      _scheduleNotifications(passes);
      _startUpdateTimer();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  Future<List<SatelliteData>> _fetchTLEs(String category) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://celestrak.org/NORAD/elements/gp.php?GROUP=$category&FORMAT=tle'),
      );

      if (response.statusCode != 200) return [];

      final lines = response.body.trim().split('\n');
      List<SatelliteData> satellites = [];

      for (int i = 0; i < lines.length; i += 3) {
        if (i + 2 < lines.length) {
          satellites.add(SatelliteData(
            name: lines[i].trim(),
            tle1: lines[i + 1].trim(),
            tle2: lines[i + 2].trim(),
            category: category.toUpperCase(),
          ));
        }
      }

      return satellites;
    } catch (e) {
      return [];
    }
  }

  List<SatellitePass> _calculatePasses(List<SatelliteData> satellites) {
    List<SatellitePass> passes = [];
    final now = DateTime.now();
    const hoursAhead = 72;
    const zenithThreshold = 80.0; // Within 10° of zenith

    for (var sat in satellites) {
      try {
        final tle = TLE(sat.name, sat.tle1, sat.tle2);
        final satellite = Satellite(tle);

        bool inPass = false;
        DateTime? passStart;
        DateTime? passEnd;
        double maxElevation = 0;
        double startAzimuth = 0;

        for (int minutes = 0; minutes < hoursAhead * 60; minutes++) {
          final time = now.add(Duration(minutes: minutes));
          final julianDate = _toJulianDate(time);

          try {
            final satPos = satellite.getPosition(julianDate);
            final obsPos = CoordGeodetic(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              0.1,
            );

            final lookAngle = satPos.getLookAngle(obsPos);
            final elevation = lookAngle.elevationDeg;
            final azimuth = lookAngle.azimuthDeg;

            if (elevation >= zenithThreshold && !inPass) {
              inPass = true;
              passStart = time;
              maxElevation = elevation;
              startAzimuth = azimuth;
            } else if (elevation >= zenithThreshold && inPass) {
              if (elevation > maxElevation) {
                maxElevation = elevation;
              }
              passEnd = time;
            } else if (elevation < zenithThreshold && inPass) {
              passes.add(SatellitePass(
                name: sat.name,
                category: sat.category,
                start: passStart!,
                end: passEnd ?? passStart!,
                maxElevation: maxElevation,
                azimuth: startAzimuth,
                power: _satellitePower[sat.category] ?? 2.0,
              ));
              inPass = false;
              passStart = null;
              passEnd = null;
              maxElevation = 0;
            }
          } catch (e) {
            // Skip this time step
          }
        }

        if (inPass && passStart != null) {
          passes.add(SatellitePass(
            name: sat.name,
            category: sat.category,
            start: passStart,
            end: passEnd ?? passStart,
            maxElevation: maxElevation,
            azimuth: startAzimuth,
            power: _satellitePower[sat.category] ?? 2.0,
          ));
        }
      } catch (e) {
        // Skip problematic satellites
      }
    }

    passes.sort((a, b) => a.start.compareTo(b.start));
    return passes;
  }

  double _toJulianDate(DateTime dateTime) {
    final a = (14 - dateTime.month) ~/ 12;
    final y = dateTime.year + 4800 - a;
    final m = dateTime.month + 12 * a - 3;

    var jdn = dateTime.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;

    final hour = dateTime.hour +
        dateTime.minute / 60.0 +
        dateTime.second / 3600.0 +
        dateTime.millisecond / 3600000.0;

    return jdn + (hour - 12) / 24.0;
  }

  void _scheduleNotifications(List<SatellitePass> passes) {
    for (var pass in passes.take(20)) {
      final notifTime = pass.start.subtract(const Duration(minutes: 5));
      if (notifTime.isAfter(DateTime.now())) {
        NotificationService.scheduleNotification(
          pass.name,
          'High-power satellite passing overhead in 5 minutes!\nElevation: ${pass.maxElevation.toStringAsFixed(1)}°',
          notifTime,
        );
      }
    }
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      setState(() {
        // Trigger UI update
      });
    });
  }

  List<SatellitePass> get _filteredPasses {
    return _passes.where((pass) {
      final powerOk = pass.power >= _powerThreshold;
      final typeOk = _selectedTypes.contains('ALL') ||
          _selectedTypes.contains(pass.category);
      return powerOk && typeOk;
    }).take(10).toList();
  }

  String _getDirection(double azimuth) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((azimuth + 22.5) / 45).floor() % 8;
    return '${directions[index]} (${azimuth.toStringAsFixed(0)}°)';
  }

  Color _getPowerColor(double power) {
    if (power >= 4.5) return Colors.red;
    if (power >= 3.5) return Colors.orange;
    if (power >= 2.5) return Colors.yellow;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.deepPurple.shade900,
              Colors.black,
              Colors.indigo.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildRadarAnimation(),
              _buildFilters(),
              Expanded(child: _buildPassList()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _loadSatellites,
        icon: _isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : const Icon(Icons.satellite_alt),
        label: Text(_isLoading ? 'Loading...' : 'Track Satellites'),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 32, color: Colors.cyanAccent),
              const SizedBox(width: 12),
              const Text(
                'EMF Satellite Tracker',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarAnimation() {
    return SizedBox(
      height: 150,
      child: AnimatedBuilder(
        animation: _radarController,
        builder: (context, child) {
          return CustomPaint(
            painter: RadarPainter(
              _radarController.value,
              _pulseController.value,
              _filteredPasses.isEmpty ? 0 : _filteredPasses.length,
            ),
            size: const Size(double.infinity, 150),
          );
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EMF Power Threshold',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _powerThreshold,
                  min: 1.0,
                  max: 5.0,
                  divisions: 8,
                  label: _powerThreshold.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() {
                      _powerThreshold = value;
                    });
                    _savePreferences();
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getPowerColor(_powerThreshold),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _powerThreshold.toStringAsFixed(1),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('ALL'),
                selected: _selectedTypes.contains('ALL'),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTypes = {'ALL'};
                    }
                  });
                },
              ),
              ...['RADAR', 'GPS-OPS', 'TDRSS', 'GOES'].map((type) {
                return FilterChip(
                  label: Text(type),
                  selected: _selectedTypes.contains(type),
                  onSelected: (selected) {
                    setState(() {
                      _selectedTypes.remove('ALL');
                      if (selected) {
                        _selectedTypes.add(type);
                      } else {
                        _selectedTypes.remove(type);
                        if (_selectedTypes.isEmpty) {
                          _selectedTypes.add('ALL');
                        }
                      }
                    });
                  },
                );
              }).toList(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPassList() {
    if (_filteredPasses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.satellite_alt,
                size: 64, color: Colors.grey.shade700),
            const SizedBox(height: 16),
            Text(
              _passes.isEmpty
                  ? 'No passes calculated yet'
                  : 'No passes match your filters',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredPasses.length,
      itemBuilder: (context, index) {
        final pass = _filteredPasses[index];
        final timeUntil = pass.start.difference(DateTime.now());
        final isImminent = timeUntil.inMinutes < 30;

        return Card(
          color: isImminent
              ? Colors.red.shade900.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getPowerColor(pass.power),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pass.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pass.category,
                  style: TextStyle(
                    color: Colors.cyanAccent.shade400,
                    fontSize: 12,
                  ),
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM dd, hh:mm a').format(pass.start),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          timeUntil.inMinutes < 60
                              ? 'in ${timeUntil.inMinutes}m'
                              : 'in ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m',
                          style: TextStyle(
                            color: isImminent
                                ? Colors.red.shade300
                                : Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${pass.maxElevation.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getDirection(pass.azimuth),
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: pass.power / 5.0,
                  backgroundColor: Colors.grey.shade800,
                  valueColor:
                  AlwaysStoppedAnimation(_getPowerColor(pass.power)),
                ),
                const SizedBox(height: 4),
                Text(
                  'EMF Power: ${pass.power.toStringAsFixed(1)}/5.0',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final double animationValue;
  final double pulseValue;
  final int targetCount;

  RadarPainter(this.animationValue, this.pulseValue, this.targetCount);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;

    // Draw radar circles
    for (int i = 1; i <= 3; i++) {
      final paint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, maxRadius * i / 3, paint);
    }

    // Draw rotating sweep
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.cyanAccent.withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    final sweepPath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: maxRadius),
        -pi / 2 + animationValue * 2 * pi,
        pi / 3,
        false,
      )
      ..lineTo(center.dx, center.dy);

    canvas.drawPath(sweepPath, sweepPaint);

    // Draw targets (satellites)
    for (int i = 0; i < targetCount && i < 5; i++) {
      final angle = (i / 5) * 2 * pi;
      final radius = maxRadius * 0.7;
      final targetPos = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );

      final targetPaint = Paint()
        ..color = Colors.red
            .withOpacity(0.5 + 0.5 * sin(pulseValue * 2 * pi));
      canvas.drawCircle(targetPos, 4, targetPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
  }

  static Future<void> scheduleNotification(
      String title,
      String body,
      DateTime scheduledTime,
      ) async {
    const androidDetails = AndroidNotificationDetails(
      'satellite_passes',
      'Satellite Passes',
      channelDescription: 'Notifications for upcoming satellite passes',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      scheduledTime.millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      scheduledTime.toLocal(),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}

class SatelliteData {
  final String name;
  final String tle1;
  final String tle2;
  final String category;

  SatelliteData({
    required this.name,
    required this.tle1,
    required this.tle2,
    required this.category,
  });
}

class SatellitePass {
  final String name;
  final String category;
  final DateTime start;
  final DateTime end;
  final double maxElevation;
  final double azimuth;
  final double power;

  SatellitePass({
    required this.name,
    required this.category,
    required this.start,
    required this.end,
    required this.maxElevation,
    required this.azimuth,
    required this.power,
  });
}