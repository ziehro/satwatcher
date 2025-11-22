import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/satellite_data.dart';
import '../models/satellite_pass.dart';
import '../services/satellite_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../widgets/radar_painter.dart';
import 'satellite_detail_screen.dart';

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
  double _zenithThreshold = 80.0;
  int _hoursAhead = 72;
  Set<String> _selectedTypes = {'ALL'};
  Timer? _updateTimer;
  late AnimationController _radarController;
  late AnimationController _pulseController;
  double _totalEMFExposure = 0.0;
  int _activePassCount = 0;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _loadPreferences();
    _loadStoredPasses();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _radarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _calculateLiveEMF();
        setState(() {});
      }
    });
    // Calculate immediately
    _calculateLiveEMF();
  }

  void _calculateLiveEMF() {
    if (_currentPosition == null || _passes.isEmpty) {
      _totalEMFExposure = 0.0;
      _activePassCount = 0;
      return;
    }

    double totalExposure = 0.0;
    int activeCount = 0;
    final now = DateTime.now();
    String nextPassInfo = "No upcoming passes";

    for (var pass in _passes) {
      // Check if satellite is currently overhead
      if (now.isAfter(pass.start) && now.isBefore(pass.end)) {
        try {
          final pos = SatelliteService.getCurrentPosition(
            pass.tle1,
            pass.tle2,
            pass.name,
            _currentPosition!,
          );

          if (pos.isNotEmpty) {
            final elevation = pos['elevation'] ?? 0.0;
            final range = pos['range'] ?? 20000.0;

            if (elevation > 0) {
              final emf = SatelliteService.calculateEMFExposure(
                pass.category,
                elevation,
                range,
              );
              totalExposure += emf['exposureMicrowatts'];
              activeCount++;
            }
          }
        } catch (e) {
          // Skip this satellite
        }
      }
    }

    // Find next pass
    for (var pass in _passes) {
      if (pass.start.isAfter(now)) {
        final timeUntil = pass.start.difference(now);
        if (timeUntil.inMinutes < 60) {
          nextPassInfo = "${pass.name} in ${timeUntil.inMinutes}m";
        } else {
          nextPassInfo = "${pass.name} in ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m";
        }
        break;
      }
    }

    setState(() {
      _totalEMFExposure = totalExposure;
      _activePassCount = activeCount;
    });

    // Update widget
    final percentOfLimit = (totalExposure / 10000.0) * 100;
    WidgetService.updateWidget(
      emfValue: totalExposure,
      satCount: activeCount,
      percentLimit: percentOfLimit,
      nextPass: nextPassInfo,
    );
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('SharedPreferences load preferences timeout');
          throw TimeoutException('Failed to load preferences');
        },
      );

      setState(() {
        _powerThreshold = prefs.getDouble('powerThreshold') ?? 1.0;
        _zenithThreshold = prefs.getDouble('zenithThreshold') ?? 80.0;
        _hoursAhead = prefs.getInt('hoursAhead') ?? 72;
      });
    } catch (e) {
      print('Error loading preferences: $e');
      // Use defaults if loading fails
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('SharedPreferences save preferences timeout');
          throw TimeoutException('Failed to save preferences');
        },
      );

      await prefs.setDouble('powerThreshold', _powerThreshold);
      await prefs.setDouble('zenithThreshold', _zenithThreshold);
      await prefs.setInt('hoursAhead', _hoursAhead);
    } catch (e) {
      print('Error saving preferences: $e');
      // Don't block the UI - just log the error
    }
  }

  Future<void> _loadStoredPasses() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('SharedPreferences timeout');
          throw TimeoutException('Failed to load preferences');
        },
      );

      final passesJson = prefs.getString('satellite_passes');
      final posLat = prefs.getDouble('position_lat');
      final posLon = prefs.getDouble('position_lon');

      if (passesJson != null && posLat != null && posLon != null) {
        final List<dynamic> decoded = jsonDecode(passesJson);
        final passes = decoded.map((e) => SatellitePass.fromJson(e)).toList();

        // Filter out expired passes
        final now = DateTime.now();
        final validPasses = passes.where((p) => p.end.isAfter(now)).toList();

        if (validPasses.isNotEmpty) {
          setState(() {
            _passes = validPasses;
            _currentPosition = Position(
              latitude: posLat,
              longitude: posLon,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
            _statusMessage = 'Loaded ${validPasses.length} stored passes';
          });

          // Reschedule notifications for loaded passes (don't await)
          _scheduleNotifications(validPasses);
          _startUpdateTimer();
        }
      }
    } catch (e) {
      print('Error loading stored passes: $e');
      // Don't block the UI - just log the error
    }
  }

  Future<void> _saveStoredPasses() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('SharedPreferences save timeout');
          throw TimeoutException('Failed to save preferences');
        },
      );

      final passesJson = jsonEncode(_passes.map((e) => e.toJson()).toList());
      await prefs.setString('satellite_passes', passesJson);

      if (_currentPosition != null) {
        await prefs.setDouble('position_lat', _currentPosition!.latitude);
        await prefs.setDouble('position_lon', _currentPosition!.longitude);
      }
    } catch (e) {
      print('Error saving stored passes: $e');
      // Don't block the UI - just log the error
    }
  }

  Future<void> _showTrackingOptions() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tracking Options'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Zenith Threshold: ${_zenithThreshold.toInt()}°'),
              Slider(
                value: _zenithThreshold,
                min: 70.0,
                max: 90.0,
                divisions: 20,
                label: '${_zenithThreshold.toInt()}°',
                onChanged: (value) {
                  setDialogState(() => _zenithThreshold = value);
                  setState(() => _zenithThreshold = value);
                },
              ),
              const SizedBox(height: 16),
              Text('Hours Ahead: $_hoursAhead'),
              Slider(
                value: _hoursAhead.toDouble(),
                min: 24,
                max: 168,
                divisions: 6,
                label: '$_hoursAhead hrs',
                onChanged: (value) {
                  setDialogState(() => _hoursAhead = value.toInt());
                  setState(() => _hoursAhead = value.toInt());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _savePreferences();
                Navigator.pop(context, true);
              },
              child: const Text('Track'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadSatellites();
    }
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

    final permissionsGranted = await NotificationService.requestPermissions();
    if (!permissionsGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification permissions required for alerts'),
          duration: Duration(seconds: 10),
        ),
      );
    }

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
        final sats = await SatelliteService.fetchTLEs(category);
        allSatellites.addAll(sats);
      }

      final passes = SatelliteService.calculatePasses(
        allSatellites,
        _currentPosition!,
        _zenithThreshold,
        _hoursAhead,
      );

      setState(() {
        _passes = passes;
        _isLoading = false;
        _statusMessage = 'Found ${passes.length} passes';
      });

      await _saveStoredPasses();
      _scheduleNotifications(passes);
      _startUpdateTimer();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  void _scheduleNotifications(List<SatellitePass> passes) {
    // Schedule in background - don't block UI
    Future.microtask(() async {
      try {
        for (var pass in passes.take(20)) {
          final passDuration = pass.end.difference(pass.start);
          final maxElevationTime = pass.start
              .add(Duration(milliseconds: passDuration.inMilliseconds ~/ 2));

          final notifTime = maxElevationTime.subtract(const Duration(minutes: 5));
          if (notifTime.isAfter(DateTime.now())) {
            await NotificationService.scheduleNotification(
              pass.name,
              'High-power satellite at max elevation in 5 minutes!\nPower: ${pass.power.toStringAsFixed(1)}/5.0 | Elevation: ${pass.maxElevation.toStringAsFixed(1)}°',
              notifTime,
            );
          }
        }
      } catch (e) {
        print('Error scheduling notifications: $e');
      }
    });
  }


  List<SatellitePass> get _filteredPasses {
    return _passes.where((pass) {
      final powerOk = pass.power >= _powerThreshold;
      final typeOk =
          _selectedTypes.contains('ALL') || _selectedTypes.contains(pass.category);
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
              _buildLiveEMFDisplay(),
              _buildFilters(),
              Expanded(child: _buildPassList()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _showTrackingOptions,
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
              const Icon(Icons.radar, size: 28, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'EMF Sat Tracker',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: _checkNotifications,
                tooltip: 'Check notifications',
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

  Future<void> _checkNotifications() async {
    final pending = await NotificationService.getPendingNotifications();
    final timerCount = NotificationService.getScheduledCount();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Scheduled Notifications'),
            Text(
              '${pending.length + timerCount}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.cyanAccent.shade400,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: pending.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No notifications scheduled.\n\nNotifications will be created automatically when you track satellites.',
              textAlign: TextAlign.center,
            ),
          )
              : ListView.builder(
            shrinkWrap: true,
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final notification = pending[index];
              // Convert notification ID back to timestamp
              final scheduledTime = DateTime.fromMillisecondsSinceEpoch(
                notification.id * 1000,
              );
              final timeUntil = scheduledTime.difference(DateTime.now());

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  title: Text(
                    notification.title ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, hh:mm a').format(scheduledTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.cyanAccent.shade400,
                        ),
                      ),
                      Text(
                        timeUntil.isNegative
                            ? 'Past due'
                            : timeUntil.inMinutes < 60
                            ? 'in ${timeUntil.inMinutes}m'
                            : 'in ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m',
                        style: TextStyle(
                          fontSize: 11,
                          color: timeUntil.isNegative
                              ? Colors.red.shade300
                              : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    color: Colors.red.shade400,
                    onPressed: () async {
                      await NotificationService.cancelNotification(
                        notification.id,
                      );
                      Navigator.pop(context);
                      _checkNotifications(); // Refresh the dialog
                    },
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          if (pending.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete All Notifications?'),
                    content: Text(
                      'This will cancel all ${pending.length} scheduled notifications.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  await NotificationService.cancelAllNotifications();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All notifications cancelled'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Delete All'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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

  Widget _buildLiveEMFDisplay() {
    if (_passes.isEmpty) return const SizedBox.shrink();

    final percentOfLimit = (_totalEMFExposure / 10000.0) * 100;
    final exposureColor = percentOfLimit >= 50
        ? Colors.red
        : percentOfLimit >= 25
        ? Colors.orange
        : percentOfLimit >= 10
        ? Colors.yellow
        : Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        color: _activePassCount > 0
            ? exposureColor.withOpacity(0.2)
            : Colors.white.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sensors,
                    color: _activePassCount > 0 ? exposureColor : Colors.grey.shade600,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVE EMF EXPOSURE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _activePassCount == 0
                              ? 'No satellites overhead'
                              : '$_activePassCount satellite${_activePassCount > 1 ? 's' : ''} overhead',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _activePassCount > 0 ? exposureColor : Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _totalEMFExposure.toStringAsFixed(3),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const Text(
                          'µW/cm²',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _activePassCount > 0 ? (percentOfLimit / 100).clamp(0.0, 1.0) : 0.0,
                backgroundColor: Colors.grey.shade800,
                valueColor: AlwaysStoppedAnimation(
                    _activePassCount > 0 ? exposureColor : Colors.grey.shade600
                ),
                minHeight: 8,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${percentOfLimit.toStringAsFixed(4)}% of safety limit',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  Text(
                    'Limit: 10,000 µW/cm²',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            Icon(Icons.satellite_alt, size: 64, color: Colors.grey.shade700),
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

        return GestureDetector(
          onTap: () {
            if (_currentPosition != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SatelliteDetailScreen(
                    pass: pass,
                    observerPosition: _currentPosition!,
                  ),
                ),
              );
            }
          },
          child: Card(
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
                      const Icon(Icons.chevron_right),
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
          ),
        );
      },
    );
  }
}