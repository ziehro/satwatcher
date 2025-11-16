import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/satellite_pass.dart';
import '../services/satellite_service.dart';
import '../widgets/sky_view_painter.dart';

class SatelliteDetailScreen extends StatefulWidget {
  final SatellitePass pass;
  final Position observerPosition;

  const SatelliteDetailScreen({
    Key? key,
    required this.pass,
    required this.observerPosition,
  }) : super(key: key);

  @override
  State<SatelliteDetailScreen> createState() => _SatelliteDetailScreenState();
}

class _SatelliteDetailScreenState extends State<SatelliteDetailScreen> {
  Map<String, dynamic>? _currentPosition;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updatePosition();
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _updatePosition();
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _updatePosition() {
    final pos = SatelliteService.getCurrentPosition(
      widget.pass.tle1,
      widget.pass.tle2,
      widget.pass.name,
      widget.observerPosition,
    );
    if (mounted) {
      setState(() {
        _currentPosition = pos;
      });
    }
  }

  Color _getPowerColor(double power) {
    if (power >= 4.5) return Colors.red;
    if (power >= 3.5) return Colors.orange;
    if (power >= 2.5) return Colors.yellow;
    return Colors.green;
  }

  String _getDirection(double azimuth) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((azimuth + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    final timeUntil = widget.pass.start.difference(DateTime.now());
    final isActive = DateTime.now().isAfter(widget.pass.start) &&
        DateTime.now().isBefore(widget.pass.end);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pass.name),
        backgroundColor: Colors.deepPurple.shade900,
      ),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isActive)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'PASS IN PROGRESS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isActive) const SizedBox(height: 16),

              // Sky View
              Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sky View',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_currentPosition != null)
                        SizedBox(
                          height: 300,
                          child: CustomPaint(
                            painter: SkyViewPainter(
                              azimuth: _currentPosition!['azimuth'] ?? 0,
                              elevation: _currentPosition!['elevation'] ?? 0,
                              observerLat: widget.observerPosition.latitude,
                              observerLon: widget.observerPosition.longitude,
                            ),
                            size: const Size(double.infinity, 300),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Current Position Info
              if (_currentPosition != null) ...[
                Card(
                  color: Colors.white.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Position',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow('Latitude', '${_currentPosition!['latitude']?.toStringAsFixed(4)}°'),
                        _buildInfoRow('Longitude', '${_currentPosition!['longitude']?.toStringAsFixed(4)}°'),
                        _buildInfoRow('Altitude', '${_currentPosition!['altitude']?.toStringAsFixed(2)} km'),
                        _buildInfoRow('Elevation', '${_currentPosition!['elevation']?.toStringAsFixed(1)}°'),
                        _buildInfoRow('Azimuth', '${_currentPosition!['azimuth']?.toStringAsFixed(1)}° (${_getDirection(_currentPosition!['azimuth'] ?? 0)})'),
                        _buildInfoRow('Range', '${_currentPosition!['range']?.toStringAsFixed(2)} km'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Pass Information
              Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pass Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Category', widget.pass.category),
                      _buildInfoRow('Start Time', DateFormat('MMM dd, yyyy hh:mm a').format(widget.pass.start)),
                      _buildInfoRow('End Time', DateFormat('MMM dd, yyyy hh:mm a').format(widget.pass.end)),
                      _buildInfoRow('Duration', '${widget.pass.end.difference(widget.pass.start).inMinutes} minutes'),
                      _buildInfoRow('Max Elevation', '${widget.pass.maxElevation.toStringAsFixed(1)}°'),
                      _buildInfoRow('Direction', '${widget.pass.azimuth.toStringAsFixed(1)}° (${_getDirection(widget.pass.azimuth)})'),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Text('EMF Power: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getPowerColor(widget.pass.power),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${widget.pass.power.toStringAsFixed(1)}/5.0',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isActive) ...[
                        const SizedBox(height: 12),
                        Text(
                          timeUntil.isNegative
                              ? 'Pass completed'
                              : timeUntil.inMinutes < 60
                              ? 'Starts in ${timeUntil.inMinutes} minutes'
                              : 'Starts in ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m',
                          style: TextStyle(
                            color: timeUntil.inMinutes < 30 && !timeUntil.isNegative
                                ? Colors.red.shade300
                                : Colors.grey.shade400,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Technical Data
              Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Technical Data (TLE)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.pass.name,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.pass.tle1,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.pass.tle2,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}