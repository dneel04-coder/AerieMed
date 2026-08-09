import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingException implements Exception {
  final String message;
  RoutingException(this.message);
  @override
  String toString() => message;
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final Duration duration;
  const RouteResult({required this.points, required this.distanceMeters, required this.duration});
}

/// One leg of a multi-stop route — the segment between two consecutive stops.
class RouteLeg {
  final double distanceMeters;
  final Duration duration;
  const RouteLeg({required this.distanceMeters, required this.duration});
}

class MultiRouteResult {
  final List<LatLng> points;
  final double totalDistanceMeters;
  final Duration totalDuration;
  final List<RouteLeg> legs;
  const MultiRouteResult({
    required this.points,
    required this.totalDistanceMeters,
    required this.totalDuration,
    required this.legs,
  });
}

/// Road-based routing via OSRM's free public demo server — no API key, but
/// a shared rate-limited service with no uptime guarantee. Acceptable for
/// this phase per explicit user choice over a paid API or a straight-line
/// distance estimate.
class OsrmRoutingService {
  static const _base = 'https://router.project-osrm.org/route/v1/driving';

  static Future<RouteResult> route(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      '$_base/${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );
    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        throw RoutingException('Routing service unavailable (HTTP ${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') throw RoutingException('No drivable route found');
      final routes = data['routes'] as List? ?? const [];
      if (routes.isEmpty) throw RoutingException('No drivable route found');
      final r = routes.first as Map<String, dynamic>;
      final coords = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return RouteResult(
        points: coords,
        distanceMeters: (r['distance'] as num).toDouble(),
        duration: Duration(seconds: (r['duration'] as num).round()),
      );
    } on TimeoutException {
      throw RoutingException('Routing service timed out — check your connection');
    } on SocketException {
      throw RoutingException('No internet connection — navigation needs connectivity');
    } catch (e) {
      if (e is RoutingException) rethrow;
      throw RoutingException('Routing failed: $e');
    }
  }

  /// Multi-stop route through 2+ points, in order — origin, any points
  /// between, and a destination. OSRM natively supports multiple waypoints
  /// in one request and returns both an overall total and a `legs` array
  /// (one entry per consecutive pair of stops), so a single call gives both
  /// the total ETA and each segment's ETA without chaining separate requests.
  static Future<MultiRouteResult> routeMultiple(List<LatLng> stops) async {
    if (stops.length < 2) throw RoutingException('Need at least an origin and a destination');
    final coordsParam = stops.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url = Uri.parse('$_base/$coordsParam?overview=full&geometries=geojson');
    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw RoutingException('Routing service unavailable (HTTP ${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') throw RoutingException('No drivable route found between those points');
      final routes = data['routes'] as List? ?? const [];
      if (routes.isEmpty) throw RoutingException('No drivable route found between those points');
      final r = routes.first as Map<String, dynamic>;
      final coords = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      final legs = (r['legs'] as List)
          .map((l) => RouteLeg(
                distanceMeters: ((l as Map<String, dynamic>)['distance'] as num).toDouble(),
                duration: Duration(seconds: (l['duration'] as num).round()),
              ))
          .toList();
      return MultiRouteResult(
        points: coords,
        totalDistanceMeters: (r['distance'] as num).toDouble(),
        totalDuration: Duration(seconds: (r['duration'] as num).round()),
        legs: legs,
      );
    } on TimeoutException {
      throw RoutingException('Routing service timed out — check your connection');
    } on SocketException {
      throw RoutingException('No internet connection — navigation needs connectivity');
    } catch (e) {
      if (e is RoutingException) rethrow;
      throw RoutingException('Routing failed: $e');
    }
  }
}

String formatDistance(double meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m';

String formatDuration(Duration d) =>
    d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes} min';
