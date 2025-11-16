class SatellitePass {
  final String name;
  final String category;
  final DateTime start;
  final DateTime end;
  final double maxElevation;
  final double azimuth;
  final double power;
  final String tle1;
  final String tle2;

  SatellitePass({
    required this.name,
    required this.category,
    required this.start,
    required this.end,
    required this.maxElevation,
    required this.azimuth,
    required this.power,
    required this.tle1,
    required this.tle2,
  });
}