import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:sgp4_sdp4/sgp4_sdp4.dart';
import 'package:geolocator/geolocator.dart';
import '../models/satellite_data.dart';
import '../models/satellite_pass.dart';

class SatelliteService {
  static const Map<String, double> satellitePower = {
    'RADAR': 5.0,
    'GPS-OPS': 3.0,
    'GALILEO': 3.0,
    'BEIDOU': 3.0,
    'GLONASS-OPS': 3.0,
    'TDRSS': 4.5,
    'SARSAT': 2.5,
    'GOES': 3.5,
    'MUSSON': 3.5,
  };

  static Future<List<SatelliteData>> fetchTLEs(String category) async {
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

  static List<SatellitePass> calculatePasses(
      List<SatelliteData> satellites,
      Position position,
      double zenithThreshold,
      int hoursAhead,
      ) {
    List<SatellitePass> passes = [];
    final now = DateTime.now();

    for (var sat in satellites) {
      try {
        final tle = TLE(sat.name, sat.tle1, sat.tle2);
        final orbit = Orbit(tle);

        bool inPass = false;
        DateTime? passStart;
        DateTime? passEnd;
        double maxElevation = 0;
        double startAzimuth = 0;

        for (int minutes = 0; minutes < hoursAhead * 60; minutes++) {
          final time = now.add(Duration(minutes: minutes));

          try {
            final jd = Julian.fromFullDate(
              time.year,
              time.month,
              time.day,
              time.hour,
              time.minute,
            ).getDate();

            final minutesSinceEpoch =
                (jd - orbit.epoch().getDate()) * MIN_PER_DAY;
            final eciPos = orbit.getPosition(minutesSinceEpoch);
            final satGeo = eciPos.toGeo();

            final obsLat = deg2rad(position.latitude);
            final obsLon = deg2rad(position.longitude);
            final obsAlt = 0.1;

            final lookAngle = calculateLookAngle(
              satGeo,
              obsLat,
              obsLon,
              obsAlt,
              time,
            );

            final elevation = lookAngle['elevation']!;
            final azimuth = lookAngle['azimuth']!;

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
                power: satellitePower[sat.category] ?? 2.0,
                tle1: sat.tle1,
                tle2: sat.tle2,
              ));
              inPass = false;
              passStart = null;
              passEnd = null;
              maxElevation = 0;
            }
          } catch (e) {
            // Skip
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
            power: satellitePower[sat.category] ?? 2.0,
            tle1: sat.tle1,
            tle2: sat.tle2,
          ));
        }
      } catch (e) {
        // Skip
      }
    }

    passes.sort((a, b) => a.start.compareTo(b.start));
    return passes;
  }

  static Map<String, double> calculateLookAngle(
      CoordGeo satGeo,
      double obsLat,
      double obsLon,
      double obsAlt,
      DateTime time,
      ) {
    double satLat = satGeo.lat;
    double satLon = satGeo.lon;
    if (satLon > PI) satLon -= TWOPI;
    double satAlt = satGeo.alt;

    final dx = (satAlt + 6378.137) * cos(satLat) * cos(satLon) -
        (obsAlt + 6378.137) * cos(obsLat) * cos(obsLon);
    final dy = (satAlt + 6378.137) * cos(satLat) * sin(satLon) -
        (obsAlt + 6378.137) * cos(obsLat) * sin(obsLon);
    final dz =
        (satAlt + 6378.137) * sin(satLat) - (obsAlt + 6378.137) * sin(obsLat);

    final range = sqrt(dx * dx + dy * dy + dz * dz);

    final elevation = asin(
      ((dx * cos(obsLat) * cos(obsLon) +
          dy * cos(obsLat) * sin(obsLon) +
          dz * sin(obsLat)) /
          range),
    );

    final azimuth = atan2(
      (dx * sin(obsLon) - dy * cos(obsLon)),
      (-dx * sin(obsLat) * cos(obsLon) -
          dy * sin(obsLat) * sin(obsLon) +
          dz * cos(obsLat)),
    );

    return {
      'elevation': rad2deg(elevation),
      'azimuth': rad2deg(azimuth < 0 ? azimuth + TWOPI : azimuth),
      'range': range,
    };
  }

  static Map<String, dynamic> getCurrentPosition(
      String tle1,
      String tle2,
      String name,
      Position observerPosition,
      ) {
    try {
      final tle = TLE(name, tle1, tle2);
      final orbit = Orbit(tle);
      final now = DateTime.now();

      final jd = Julian.fromFullDate(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ).getDate();

      final minutesSinceEpoch = (jd - orbit.epoch().getDate()) * MIN_PER_DAY;
      final eciPos = orbit.getPosition(minutesSinceEpoch);
      final satGeo = eciPos.toGeo();

      final obsLat = deg2rad(observerPosition.latitude);
      final obsLon = deg2rad(observerPosition.longitude);

      final lookAngle = calculateLookAngle(satGeo, obsLat, obsLon, 0.1, now);

      return {
        'latitude': rad2deg(satGeo.lat),
        'longitude': rad2deg(satGeo.lon > PI ? satGeo.lon - TWOPI : satGeo.lon),
        'altitude': satGeo.alt,
        'elevation': lookAngle['elevation'],
        'azimuth': lookAngle['azimuth'],
        'range': lookAngle['range'],
      };
    } catch (e) {
      return {};
    }
  }
}