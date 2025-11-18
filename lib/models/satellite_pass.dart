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

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'maxElevation': maxElevation,
    'azimuth': azimuth,
    'power': power,
    'tle1': tle1,
    'tle2': tle2,
  };

  factory SatellitePass.fromJson(Map<String, dynamic> json) => SatellitePass(
    name: json['name'],
    category: json['category'],
    start: DateTime.parse(json['start']),
    end: DateTime.parse(json['end']),
    maxElevation: json['maxElevation'],
    azimuth: json['azimuth'],
    power: json['power'],
    tle1: json['tle1'],
    tle2: json['tle2'],
  );
}