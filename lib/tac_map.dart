import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:battery_plus/battery_plus.dart';
import 'package:archive/archive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;
import 'gps_tools.dart';
import 'lz_assessment.dart';
import 'offline_maps.dart';
import 'sun_weather.dart';

// ftp.wildfire.gov uses a government CA not in Dart's default trust store.
// Returns an http.Client that skips cert verification for that host only.
http.Client _wildfireClient() => IOClient(
      HttpClient()
        ..badCertificateCallback =
            (cert, host, port) => host.endsWith('wildfire.gov'),
    );


enum _BaseLayer {
  osm,
  usgsTopo,
  usgsImagery,
  satellite;

  String get label => switch (this) {
        osm => 'OpenStreetMap',
        usgsTopo => 'USGS Topo',
        usgsImagery => 'USGS Imagery+Topo',
        satellite => 'Satellite',
      };

  String get urlTemplate => switch (this) {
        osm => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        usgsTopo =>
          'https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}',
        usgsImagery =>
          'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}',
        satellite =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      };
}


class _IncidentOverlay {
  final String name;
  final Uint8List imageBytes;
  final LatLngBounds bounds;
  const _IncidentOverlay(
      {required this.name, required this.imageBytes, required this.bounds});
}

const _kSupabaseUrl = 'tac_supabase_url';
const _kSupabaseKey = 'tac_supabase_anon_key';
const _kCallsign = 'tac_callsign';
const _kMissionCode = 'tac_mission_code';
const _kIsAdmin = 'tac_is_admin';
const _kUserId = 'tac_user_id';

enum TacMarkerType {
  patient,
  extractionStart,
  extractionEnd,
  waypoint;

  String get label => switch (this) {
        patient        => 'Patient',
        extractionStart => 'Extract Start',
        extractionEnd  => 'Extract End',
        waypoint       => 'Waypoint',
      };

  Color get color => switch (this) {
        patient        => Colors.red,
        extractionStart => Colors.orange,
        extractionEnd  => Colors.green,
        waypoint       => const Color(0xFF9C27B0),
      };

  IconData get icon => switch (this) {
        patient        => Icons.personal_injury,
        extractionStart => Icons.flag,
        extractionEnd  => Icons.local_hospital,
        waypoint       => Icons.place,
      };
}

// ── Check-in statuses ─────────────────────────────────────────────────────────
const _kStatuses = [
  'Active', 'En Route', 'On Scene', 'At Hospital', 'Standby', 'Off Duty',
];

Color _statusColor(String s) => switch (s) {
  'Active'      => Colors.teal,
  'En Route'    => Colors.amber,
  'On Scene'    => Colors.green,
  'At Hospital' => Colors.purple,
  'Standby'     => Colors.orange,
  'Off Duty'    => Colors.grey,
  _             => Colors.teal,
};

// ── Zone types ────────────────────────────────────────────────────────────────
const _kZoneTypes = ['Perimeter', 'LZ', 'Base Camp', 'Staging', 'Custom'];

class TacZone {
  final String id, missionCode, name, zoneType, createdBy;
  final double lat, lng, radiusM;

  TacZone({required this.id, required this.missionCode, required this.name,
      required this.zoneType, required this.lat, required this.lng,
      required this.radiusM, required this.createdBy});

  Color get color => switch (zoneType) {
    'Perimeter' => Colors.red,
    'LZ'        => Colors.cyan,
    'Base Camp' => Colors.green,
    'Staging'   => Colors.orange,
    _           => Colors.purple,
  };

  factory TacZone.fromMap(Map<String, dynamic> m) => TacZone(
      id: m['id'] as String,
      missionCode: m['mission_code'] as String? ?? '',
      name: m['name'] as String? ?? 'Zone',
      zoneType: m['zone_type'] as String? ?? 'Custom',
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      radiusM: (m['radius_m'] as num).toDouble(),
      createdBy: m['created_by'] as String? ?? '');
}

// ── SOS event ─────────────────────────────────────────────────────────────────
class TacSosEvent {
  final String id, userId, callsign, missionCode;
  final double lat, lng;
  final DateTime triggeredAt;
  final bool resolved;

  TacSosEvent({required this.id, required this.userId, required this.callsign,
      required this.missionCode, required this.lat, required this.lng,
      required this.triggeredAt, required this.resolved});

  factory TacSosEvent.fromMap(Map<String, dynamic> m) => TacSosEvent(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      callsign: m['callsign'] as String? ?? 'Unknown',
      missionCode: m['mission_code'] as String? ?? '',
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      triggeredAt: DateTime.tryParse(m['triggered_at'] as String? ?? '') ?? DateTime.now(),
      resolved: m['resolved_at'] != null);
}

class TacUser {
  final String id;
  final String callsign;
  final String missionCode;
  final double lat;
  final double lng;
  final bool isAdmin;
  final DateTime updatedAt;
  final int? batteryLevel;
  final String status;

  TacUser({
    required this.id,
    required this.callsign,
    required this.missionCode,
    required this.lat,
    required this.lng,
    required this.isAdmin,
    required this.updatedAt,
    this.batteryLevel,
    this.status = 'Active',
  });

  factory TacUser.fromMap(Map<String, dynamic> m) => TacUser(
        id: m['id'] as String,
        callsign: m['callsign'] as String,
        missionCode: m['mission_code'] as String? ?? '',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        isAdmin: m['is_admin'] as bool? ?? false,
        updatedAt: _parseTs(m['updated_at'] as String?),
        batteryLevel: m['battery_level'] as int?,
        status: m['status'] as String? ?? 'Active',
      );

  // Parse Supabase timestamps robustly — handle space separator, bare +00, etc.
  static DateTime _parseTs(String? s) {
    if (s == null || s.isEmpty) return DateTime(2000);
    var n = s.trim()
        // "2025-01-15 12:34:56+00" → "2025-01-15T12:34:56+00"
        .replaceFirstMapped(
            RegExp(r'^(\d{4}-\d{2}-\d{2}) '), (m) => '${m[1]}T')
        // "+00" without ":00" → "+00:00"
        .replaceFirstMapped(
            RegExp(r'([+-]\d{2})$'), (m) => '${m[1]}:00');
    return DateTime.tryParse(n) ??
        // Last resort: strip timezone entirely, treat as UTC
        DateTime.tryParse(n.replaceAll(RegExp(r'[+-]\d{2}:\d{2}$'), 'Z')) ??
        DateTime(2000);
  }
}

class TacMarker {
  final String id;
  final TacMarkerType type;
  final String label;
  final double lat;
  final double lng;
  final String placedBy;
  final DateTime createdAt;

  TacMarker({
    required this.id,
    required this.type,
    required this.label,
    required this.lat,
    required this.lng,
    required this.placedBy,
    required this.createdAt,
  });

  factory TacMarker.fromMap(Map<String, dynamic> m) => TacMarker(
        id: m['id'] as String,
        type: TacMarkerType.values.firstWhere(
          (t) => t.name == (m['type'] as String),
          orElse: () => TacMarkerType.patient,
        ),
        label: m['label'] as String? ?? '',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        placedBy: m['placed_by'] as String,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// TAK / ATAK INTEGRATION — team_positions table
// ═══════════════════════════════════════════════════════════════════════════

class TakPosition {
  final String id;
  final String callsign;
  final double lat;
  final double lon;
  final String role;
  final String status;
  final DateTime lastUpdated;

  TakPosition({
    required this.id,
    required this.callsign,
    required this.lat,
    required this.lon,
    required this.role,
    required this.status,
    required this.lastUpdated,
  });

  factory TakPosition.fromMap(Map<String, dynamic> m) => TakPosition(
        id: m['id'] as String? ?? '',
        callsign: m['callsign'] as String? ?? 'Unknown',
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lon: (m['lon'] as num?)?.toDouble() ?? 0,
        role: m['role'] as String? ?? '',
        status: m['status'] as String? ?? 'Unknown',
        lastUpdated: DateTime.tryParse(m['last_updated'] as String? ?? '') ?? DateTime.now(),
      );

  Color get statusColor => switch (status.toLowerCase()) {
        'active' || 'green'    => Colors.greenAccent,
        'caution' || 'yellow'  => Colors.amberAccent,
        'emergency' || 'red'   => Colors.redAccent,
        _                      => Colors.cyanAccent,
      };
}

class TacPoi {
  final String id;
  final String name;
  final String type;
  final double lat;
  final double lng;
  final String notes;

  const TacPoi({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    this.notes = '',
  });

  factory TacPoi.fromMap(Map<String, dynamic> m) => TacPoi(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? 'POI',
        type: m['type'] as String? ?? 'generic',
        lat: (m['lat'] as num?)?.toDouble() ?? 0,
        lng: (m['lng'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
      );

  IconData get icon => switch (type.toLowerCase()) {
        'medical'   => Icons.local_hospital,
        'lz'        => Icons.flight_land,
        'staging'   => Icons.flag,
        'hazard'    => Icons.warning_amber,
        'rally'     => Icons.people,
        _           => Icons.place,
      };

  Color get color => switch (type.toLowerCase()) {
        'medical'  => Colors.greenAccent,
        'lz'       => Colors.cyanAccent,
        'staging'  => Colors.orangeAccent,
        'hazard'   => Colors.redAccent,
        'rally'    => Colors.purpleAccent,
        _          => Colors.white70,
      };
}

// ── Offline-capable tile provider using disk cache ───────────────────────────
// Tiles are persisted to the device using flutter_cache_manager (bundled with
// cached_network_image). Cache key includes z/x/y so each tile is stored
// individually and survives app restarts for no-signal environments.
class _CachedTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(
      TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheKey: 'tile_${coordinates.z}_${coordinates.x}_${coordinates.y}',
    );
  }
}

// ── Dark CartoDB tile URL (default for tactical dark-theme use) ───────────────
const _kDarkTileUrl =
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
const _kDarkTileAttrib =
    '© OpenStreetMap contributors © CARTO';

// ═══════════════════════════════════════════════════════════════════════════

class TacMapScreen extends StatefulWidget {
  const TacMapScreen({super.key});

  @override
  State<TacMapScreen> createState() => _TacMapScreenState();
}

enum _Phase { loading, noConfig, noSession, active }

class _TacMapScreenState extends State<TacMapScreen> {
  _Phase _phase = _Phase.loading;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    // Use saved credentials if present, otherwise fall back to built-in defaults.
    final url = prefs.getString(_kSupabaseUrl)?.isNotEmpty == true
        ? prefs.getString(_kSupabaseUrl)!
        : 'https://vlgiclyuxaleyusalexo.supabase.co';
    final key = prefs.getString(_kSupabaseKey)?.isNotEmpty == true
        ? prefs.getString(_kSupabaseKey)!
        : 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';
    // Write defaults back so the config screen shows them if opened.
    if (prefs.getString(_kSupabaseUrl)?.isEmpty != false) {
      await prefs.setString(_kSupabaseUrl, url);
      await prefs.setString(_kSupabaseKey, key);
    }

    await SupabaseService.ensureInitialized();

    final callsign = prefs.getString(_kCallsign) ?? '';
    final mission = prefs.getString(_kMissionCode) ?? '';
    if (callsign.isEmpty || mission.isEmpty) {
      setState(() => _phase = _Phase.noSession);
      return;
    }

    setState(() => _phase = _Phase.active);
  }

  void _onConfigSaved() => _init();
  void _onLeft() => setState(() => _phase = _Phase.noSession);

  @override
  Widget build(BuildContext context) => switch (_phase) {
        _Phase.loading  => const Scaffold(body: Center(child: CircularProgressIndicator())),
        _Phase.noConfig => _SupabaseConfigScreen(onSaved: _onConfigSaved),
        // ATAK map is always shown — mission is optional, managed inside the screen
        _ => _ActiveMapScreen(onLeft: _onLeft),
      };
}

// ── Live TAK map — visible immediately without joining a mission ──────────────

class _TakLiveScreen extends StatefulWidget {
  final VoidCallback onJoinMission;
  const _TakLiveScreen({required this.onJoinMission});

  @override
  State<_TakLiveScreen> createState() => _TakLiveScreenState();
}

class _TakLiveScreenState extends State<_TakLiveScreen> {
  final _mapCtrl = MapController();
  LatLng? _myLocation;
  final Map<String, TakPosition> _takPositions = {};
  final List<TacPoi> _pois = [];
  bool _showTak = true;
  bool _showPoi = true;
  RealtimeChannel? _channel;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Get device location for initial centre
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_mapReady && _myLocation != null) _mapCtrl.move(_myLocation!, 13);
    } catch (_) {}

    // Load TAK data
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    final client = SupabaseService.client!;
    try {
      final rows = await client.from('team_positions').select() as List;
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          final p = TakPosition.fromMap(r as Map<String, dynamic>);
          _takPositions[p.callsign] = p;
        }
      });
    } catch (_) {}
    try {
      final rows = await client.from('tac_pois').select() as List;
      if (!mounted) return;
      setState(() {
        _pois.clear();
        _pois.addAll(rows.map((r) => TacPoi.fromMap(r as Map<String, dynamic>)));
      });
    } catch (_) {}

    // Realtime subscription
    _channel = client
        .channel('tak_live_preview')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'team_positions',
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final cs = payload.oldRecord['callsign'] as String?;
                if (cs != null) setState(() => _takPositions.remove(cs));
              } else {
                final p = TakPosition.fromMap(payload.newRecord);
                setState(() => _takPositions[p.callsign] = p);
              }
            })
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }

  void _showSheet(TakPosition p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                backgroundColor: p.statusColor.withValues(alpha: 0.2),
                child: Icon(Icons.person_pin, color: p.statusColor, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.callsign, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(p.role, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: p.statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.statusColor)),
              child: Text(p.status,
                  style: TextStyle(color: p.statusColor,
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const Divider(color: Colors.white12, height: 24),
          _row(Icons.gps_fixed, 'Position',
              '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}'),
          const SizedBox(height: 8),
          _row(Icons.access_time, 'Last seen', _ago(p.lastUpdated)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white70),
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Centre on this position'),
              onPressed: () {
                Navigator.pop(context);
                _mapCtrl.move(LatLng(p.lat, p.lon), 15);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 15, color: Colors.white38),
        const SizedBox(width: 8),
        Text('$label  ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(child: Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
      ]);

  @override
  Widget build(BuildContext context) {
    final stale = DateTime.now().subtract(const Duration(minutes: 5));

    final takMarkers = _showTak
        ? _takPositions.values.map((p) {
            final isStale = p.lastUpdated.isBefore(stale);
            final col = isStale ? Colors.white24 : p.statusColor;
            return Marker(
              point: LatLng(p.lat, p.lon),
              width: 88, height: 60,
              child: GestureDetector(
                onTap: () => _showSheet(p),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 84),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: col, width: 1.5),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(p.callsign, maxLines: 1, overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: col, fontSize: 9, fontWeight: FontWeight.bold)),
                      Text(_ago(p.lastUpdated),
                          style: TextStyle(color: col.withValues(alpha: 0.7), fontSize: 7)),
                    ]),
                  ),
                  Icon(Icons.navigation, color: col, size: 28,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
                ]),
              ),
            );
          }).toList()
        : <Marker>[];

    final poiMarkers = _showPoi
        ? _pois.map((poi) => Marker(
            point: LatLng(poi.lat, poi.lng),
            width: 64, height: 52,
            child: GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: const Color(0xFF1A1A2E),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  child: Column(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(poi.icon, color: poi.color, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Text(poi.name,
                          style: const TextStyle(fontSize: 17,
                              fontWeight: FontWeight.bold, color: Colors.white))),
                    ]),
                    if (poi.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(poi.notes, style: const TextStyle(color: Colors.white70)),
                    ],
                  ]),
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: poi.color),
                  ),
                  child: Text(poi.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: poi.color, fontSize: 8, fontWeight: FontWeight.w600)),
                ),
                Icon(poi.icon, color: poi.color, size: 24,
                    shadows: const [Shadow(color: Colors.black87, blurRadius: 3)]),
              ]),
            ),
          )).toList()
        : <Marker>[];

    // ATAK-style layout: full-screen map with overlay panels, no standard AppBar
    const bg = Color(0xFF0D1117);
    const fg = Colors.white;
    const dim = Color(0xFF8B949E);
    const cyan = Colors.cyanAccent;

    final mapCenter = _mapReady ? _mapCtrl.camera.center : (_myLocation ?? const LatLng(37.0902, -95.7129));
    final zoom = _mapReady ? _mapCtrl.camera.zoom : 13.0;
    final latStr = mapCenter.latitude.toStringAsFixed(5);
    final lonStr = mapCenter.longitude.toStringAsFixed(5);

    return Scaffold(
      backgroundColor: Colors.black,
      // No AppBar — ATAK is full-screen map
      body: SafeArea(
        child: Stack(children: [
          // ── Full-screen map ───────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(37.0902, -95.7129),
              initialZoom: _myLocation != null ? 13 : 4,
              onMapReady: () {
                _mapReady = true;
                if (_myLocation != null) _mapCtrl.move(_myLocation!, 13);
              },
              onPositionChanged: (_, __) => setState(() {}),
            ),
            children: [
              TileLayer(
                urlTemplate: _kDarkTileUrl,
                userAgentPackageName: 'com.resqruck.app',
                tileProvider: _CachedTileProvider(),
              ),
              if (takMarkers.isNotEmpty) MarkerLayer(markers: takMarkers),
              if (poiMarkers.isNotEmpty) MarkerLayer(markers: poiMarkers),
              if (_myLocation != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _myLocation!,
                    width: 24, height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
                      ),
                    ),
                  ),
                ]),
            ],
          ),

          // ── Top header bar (ATAK style) ───────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: bg.withValues(alpha: 0.88),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                // Grid/heading indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: cyan.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('TAK', style: TextStyle(color: cyan,
                      fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                const SizedBox(width: 8),
                if (_takPositions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: cyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${_takPositions.length} LIVE',
                        style: const TextStyle(color: cyan, fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                // GPS fix indicator
                Icon(Icons.gps_fixed, size: 13,
                    color: _myLocation != null ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 4),
                Text(_myLocation != null ? 'GPS FIX' : 'NO FIX',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold,
                        color: _myLocation != null ? Colors.greenAccent : Colors.redAccent)),
              ]),
            ),
          ),

          // ── Right tool panel (vertical) ───────────────────────────────────
          Positioned(
            right: 8, top: 50,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _atakTool(Icons.add, 'Zoom in', bg, fg, () {
                  final z = (zoom + 1).clamp(3.0, 20.0);
                  _mapCtrl.move(_mapCtrl.camera.center, z);
                }),
                const SizedBox(height: 2),
                _atakTool(Icons.remove, 'Zoom out', bg, fg, () {
                  final z = (zoom - 1).clamp(3.0, 20.0);
                  _mapCtrl.move(_mapCtrl.camera.center, z);
                }),
                const SizedBox(height: 8),
                _atakTool(Icons.my_location, 'Re-centre', bg,
                    _myLocation != null ? cyan : Colors.white30, () {
                  if (_myLocation != null) _mapCtrl.move(_myLocation!, 14);
                }),
                const SizedBox(height: 8),
                _atakTool(Icons.radar, 'TAK layer', bg,
                    _showTak ? cyan : Colors.white30,
                    () => setState(() => _showTak = !_showTak)),
                const SizedBox(height: 2),
                _atakTool(Icons.place, 'POI layer', bg,
                    _showPoi ? Colors.orangeAccent : Colors.white30,
                    () => setState(() => _showPoi = !_showPoi)),
                const SizedBox(height: 8),
                _atakTool(Icons.refresh, 'Refresh', bg, dim, _init),
                const SizedBox(height: 8),
                _atakTool(Icons.group_add, 'Join Mission', Colors.teal, fg,
                    widget.onJoinMission),
              ],
            ),
          ),

          // ── Compass (top-right, ATAK style) ──────────────────────────────
          Positioned(
            top: 52, right: 60,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: bg.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(alignment: Alignment.center, children: [
                const Text('N', style: TextStyle(color: Colors.redAccent,
                    fontSize: 11, fontWeight: FontWeight.bold, height: 1)),
                Positioned(
                  bottom: 4,
                  child: Text('S', style: TextStyle(color: dim, fontSize: 8)),
                ),
              ]),
            ),
          ),

          // ── Zoom level badge ──────────────────────────────────────────────
          Positioned(
            top: 52, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: bg.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white10),
              ),
              child: Text('Z${zoom.round()}',
                  style: TextStyle(color: dim, fontSize: 10,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),

          // ── Empty state ────────────────────────────────────────────────────
          if (_takPositions.isEmpty && _pois.isEmpty)
            Center(
              child: IgnorePointer(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.radar_outlined, size: 56,
                      color: cyan.withValues(alpha: 0.3)),
                  const SizedBox(height: 10),
                  const Text('Waiting for ATAK feed…',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ]),
              ),
            ),

          // ── Bottom coordinate / info bar ──────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: bg.withValues(alpha: 0.92),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                // Coordinates
                Icon(Icons.gps_not_fixed, size: 12, color: dim),
                const SizedBox(width: 5),
                Text('$latStr, $lonStr',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11,
                        fontFamily: 'monospace')),
                const Spacer(),
                // Active TAK contacts
                if (_takPositions.isNotEmpty) ...[
                  Icon(Icons.people_outline, size: 12, color: cyan),
                  const SizedBox(width: 3),
                  Text('${_takPositions.length}',
                      style: const TextStyle(color: cyan, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                ],
                // POI count
                if (_pois.isNotEmpty) ...[
                  Icon(Icons.place_outlined, size: 12,
                      color: Colors.orangeAccent),
                  const SizedBox(width: 3),
                  Text('${_pois.length}',
                      style: const TextStyle(color: Colors.orangeAccent,
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _atakTool(IconData icon, String tip, Color bg, Color fg, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10),
          ),
          child: Icon(icon, color: fg, size: 18),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SupabaseConfigScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const _SupabaseConfigScreen({required this.onSaved});

  @override
  State<_SupabaseConfigScreen> createState() => _SupabaseConfigScreenState();
}

class _SupabaseConfigScreenState extends State<_SupabaseConfigScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _saving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kSupabaseUrl)?.isNotEmpty == true
        ? prefs.getString(_kSupabaseUrl)!
        : 'https://vlgiclyuxaleyusalexo.supabase.co';
    final key = prefs.getString(_kSupabaseKey)?.isNotEmpty == true
        ? prefs.getString(_kSupabaseKey)!
        : 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';
    if (mounted) {
      _urlCtrl.text = url;
      _keyCtrl.text = key;
    }
  }

  /// Strips any path/query from the URL — Supabase needs the bare project host.
  static String _cleanUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return '';
    if (!u.startsWith('http')) u = 'https://$u';
    try {
      final uri = Uri.parse(u);
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      return u.replaceAll(RegExp(r'/+$'), '');
    }
  }

  Future<void> _save() async {
    final url = _cleanUrl(_urlCtrl.text);
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _errorMsg = 'Both URL and key are required.');
      return;
    }
    setState(() { _saving = true; _errorMsg = null; });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseUrl, url);
    await prefs.setString(_kSupabaseKey, key);

    // Reset Supabase init state so ensureInitialized re-runs with new creds.
    SupabaseService.reset();
    final ok = await SupabaseService.ensureInitialized();

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _errorMsg = 'Could not connect. Check that the URL and Anon Key are correct.';
      });
      return;
    }
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Supabase Config')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Connect to your Supabase project. Run the SQL below in the Supabase SQL Editor first, '
            'then enter your Project URL and Anon Key.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          _SqlBlock(),
          const SizedBox(height: 24),
          TextField(
            controller: _urlCtrl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Project URL',
              hintText: 'https://xxxxxxxxxxxx.supabase.co',
              helperText: 'Copy from Supabase → Project Settings → API',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Anon Public Key',
              helperText: 'The "anon" key — NOT the service_role key',
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMsg!,
                    style: const TextStyle(color: Colors.red, fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save & Connect'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SqlBlock extends StatelessWidget {
  static const _sql = '''
create table if not exists tac_users (
  id text not null,
  mission_code text not null,
  callsign text not null,
  lat double precision not null,
  lng double precision not null,
  is_admin boolean default false,
  updated_at timestamptz default now(),
  primary key (id, mission_code)
);
create table if not exists tac_markers (
  id uuid default gen_random_uuid() primary key,
  mission_code text not null,
  type text not null,
  label text default '',
  lat double precision not null,
  lng double precision not null,
  placed_by text not null,
  created_at timestamptz default now()
);
alter table tac_users enable row level security;
alter table tac_markers enable row level security;
do \$\$ begin
  create policy "public_access" on tac_users
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;
do \$\$ begin
  create policy "public_access" on tac_markers
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;
do \$\$ begin
  alter publication supabase_realtime add table tac_users;
exception when others then null; end \$\$;
do \$\$ begin
  alter publication supabase_realtime add table tac_markers;
exception when others then null; end \$\$;''';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const SelectableText(_sql, style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
    );
  }
}

class _MissionSetupScreen extends StatefulWidget {
  final VoidCallback onJoined;
  const _MissionSetupScreen({required this.onJoined});

  @override
  State<_MissionSetupScreen> createState() => _MissionSetupScreenState();
}

class _MissionSetupScreenState extends State<_MissionSetupScreen> {
  final _callsignCtrl = TextEditingController();
  final _missionCtrl = TextEditingController();
  bool _isAdmin = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_kCallsign) ?? '';
      if (saved.isNotEmpty && mounted) _callsignCtrl.text = saved;
    });
  }

  Future<void> _join() async {
    final callsign = _callsignCtrl.text.trim().toUpperCase();
    final mission = _missionCtrl.text.trim().toUpperCase();
    if (callsign.isEmpty || mission.isEmpty) return;
    setState(() => _joining = true);

    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(_kUserId);
    if (userId == null) {
      userId = _randomId();
      await prefs.setString(_kUserId, userId);
    }
    await prefs.setString(_kCallsign, callsign);
    await prefs.setString(_kMissionCode, mission);
    await prefs.setBool(_kIsAdmin, _isAdmin);

    widget.onJoined();
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _missionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tac Map — Join Mission')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.radar, size: 64, color: Colors.teal),
          const SizedBox(height: 24),
          TextField(
            controller: _callsignCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Callsign',
              hintText: 'MEDIC-1',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _missionCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Mission Code',
              hintText: 'ALPHA-01',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Admin'),
            subtitle: const Text('Can view all missions and delete any marker'),
            value: _isAdmin,
            onChanged: (v) => setState(() => _isAdmin = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _joining ? null : _join,
              icon: const Icon(Icons.login),
              label: _joining ? const Text('Joining…') : const Text('Join Mission'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ActiveMapScreen extends StatefulWidget {
  final VoidCallback onLeft;
  const _ActiveMapScreen({required this.onLeft});

  @override
  State<_ActiveMapScreen> createState() => _ActiveMapScreenState();
}

class _ActiveMapScreenState extends State<_ActiveMapScreen> {
  final _mapCtrl = MapController();
  final _supabase = Supabase.instance.client;

  String _userId = '';
  String _callsign = '';
  String _missionCode = '';
  bool _isAdmin = false;

  final Map<String, TacUser> _users = {};
  final Map<String, TacMarker> _markers = {};

  RealtimeChannel? _realtimeChannel;
  Timer? _locationTimer;
  Timer? _refreshTimer;

  bool _mapReady = false;
  LatLng? _myLocation;
  TacMarkerType? _placingType;
  _BaseLayer _baseLayer = _BaseLayer.osm;
  _IncidentOverlay? _incidentOverlay;
  bool _markerTableWarned = false;
  bool _sharingLocation = true;
  bool _showAllMissions = true;
  bool _hasMission = false; // true once callsign + missionCode are set

  // Life360-style features
  final Battery _batteryPlugin = Battery();
  int? _myBattery;
  String _myStatus = 'Active';
  final Map<String, List<LatLng>> _breadcrumbs = {};
  int _breadcrumbTick = 0;
  bool _showTrails = true;
  final List<TacZone> _zones = [];
  final List<TacSosEvent> _activeSos = [];
  bool _placingZone = false;

  // TAK / ATAK layer
  final Map<String, TakPosition> _takPositions = {};
  final List<TacPoi> _pois = [];
  bool _showTakLayer = true;
  bool _showPoiLayer = true;
  RealtimeChannel? _takChannel;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString(_kUserId) ?? '';
    _callsign = prefs.getString(_kCallsign) ?? '';
    _missionCode = prefs.getString(_kMissionCode) ?? '';
    _isAdmin = prefs.getBool(_kIsAdmin) ?? false;
    _hasMission = _callsign.isNotEmpty && _missionCode.isNotEmpty;

    // Clean up own stale row
    if (_userId.isNotEmpty) {
      try { await _supabase.from('tac_users').delete().eq('id', _userId); } catch (_) {}
    }

    _readBattery();
    await _requestLocation();
    // Only broadcast location when in an active mission
    if (_hasMission) _startLocationPublish();
    _subscribeRealtime();
    _loadInitialData();
    _subscribeTakPositions();
    _loadTakData();
  }

  /// Join a mission — shows setup sheet, then enables location broadcast.
  Future<void> _joinMission() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MissionSetupScreen(onJoined: () {
        Navigator.pop(context);
        _reloadMissionState();
      }),
    );
  }

  Future<void> _reloadMissionState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _callsign = prefs.getString(_kCallsign) ?? '';
        _missionCode = prefs.getString(_kMissionCode) ?? '';
        _isAdmin = prefs.getBool(_kIsAdmin) ?? false;
        _hasMission = _callsign.isNotEmpty && _missionCode.isNotEmpty;
      });
    }
    if (_hasMission) _startLocationPublish();
  }

  // ── TAK / ATAK integration ────────────────────────────────────────────────

  Future<void> _loadTakData() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) return;
    final client = SupabaseService.client!;
    // team_positions (ATAK CoT feed)
    try {
      final rows = await client.from('team_positions').select() as List;
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          final p = TakPosition.fromMap(r as Map<String, dynamic>);
          _takPositions[p.callsign] = p;
        }
      });
    } catch (_) {}
    // POIs — optional table, degrade gracefully if absent
    try {
      final rows = await client.from('tac_pois').select() as List;
      if (!mounted) return;
      setState(() {
        _pois.clear();
        _pois.addAll(rows.map((r) => TacPoi.fromMap(r as Map<String, dynamic>)));
      });
    } catch (_) {}
  }

  void _subscribeTakPositions() {
    final client = SupabaseService.client;
    if (client == null) return;
    _takChannel = client
        .channel('tak_positions')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'team_positions',
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final cs = payload.oldRecord['callsign'] as String?;
                if (cs != null) setState(() => _takPositions.remove(cs));
              } else {
                final p = TakPosition.fromMap(payload.newRecord);
                setState(() => _takPositions[p.callsign] = p);
              }
            })
        .subscribe();
  }

  void _showTakSheet(TakPosition p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: p.statusColor.withValues(alpha: 0.2),
              child: Icon(Icons.person_pin, color: p.statusColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.callsign, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(p.role, style: TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: p.statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.statusColor, width: 1)),
              child: Text(p.status,
                  style: TextStyle(color: p.statusColor, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const Divider(color: Colors.white12, height: 24),
          _takRow(Icons.gps_fixed, 'Position',
              '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}'),
          const SizedBox(height: 8),
          _takRow(Icons.access_time, 'Last Updated', _fmtTakTime(p.lastUpdated)),
          const SizedBox(height: 8),
          _takRow(Icons.military_tech, 'Role', p.role.isEmpty ? '—' : p.role),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white70),
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Centre map on this position'),
              onPressed: () {
                Navigator.pop(context);
                _mapCtrl.move(LatLng(p.lat, p.lon), 15);
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showPoiSheet(TacPoi poi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: poi.color.withValues(alpha: 0.2),
              child: Icon(poi.icon, color: poi.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(poi.name, style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(poi.type.toUpperCase(),
                  style: TextStyle(color: poi.color, fontSize: 12, letterSpacing: 0.8)),
            ])),
          ]),
          if (poi.notes.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 24),
            Text(poi.notes, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.white70),
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Centre map on POI'),
              onPressed: () {
                Navigator.pop(context);
                _mapCtrl.move(LatLng(poi.lat, poi.lng), 15);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _takRow(IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Text('$label  ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(child: Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
      ]);

  String _fmtTakTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Future<void> _readBattery() async {
    try {
      final level = await _batteryPlugin.batteryLevel;
      if (mounted) setState(() => _myBattery = level);
      // Refresh battery every 5 minutes
      Timer.periodic(const Duration(minutes: 5), (_) async {
        try {
          final l = await _batteryPlugin.batteryLevel;
          if (mounted) setState(() => _myBattery = l);
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _requestLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_mapReady) _mapCtrl.move(_myLocation!, 14);
    } catch (_) {}
  }

  void _startLocationPublish() {
    _publishLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _publishLocation());
  }

  Future<void> _stopSharing() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    try {
      await _supabase.from('tac_users').delete()
          .eq('id', _userId).eq('mission_code', _missionCode);
    } catch (_) {}
    if (mounted) setState(() { _sharingLocation = false; _users.remove(_userId); });
  }

  void _startSharing() {
    if (_sharingLocation) return;
    setState(() => _sharingLocation = true);
    _startLocationPublish();
  }

  Future<void> _clearMarkersByType(TacMarkerType type) async {
    final toDelete = _markers.values.where((m) => m.type == type).map((m) => m.id).toList();
    for (final id in toDelete) {
      await _deleteMarker(id);
    }
    if (mounted) setState(() { for (final id in toDelete) { _markers.remove(id); } });
  }

  Future<void> _publishLocation() async {
    if (!_sharingLocation) return;
    if (_myLocation == null) {
      try {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        _myLocation = LatLng(pos.latitude, pos.longitude);
        if (mounted) setState(() {});
      } catch (_) {
        return;
      }
    } else {
      try {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
        if (mounted) setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      } catch (_) {}
    }
    if (_myLocation == null) return;
    // Optimistically show ourselves immediately without waiting for the channel
    if (mounted) {
      setState(() {
        _users[_userId] = TacUser(
          id: _userId, callsign: _callsign, missionCode: _missionCode,
          lat: _myLocation!.latitude, lng: _myLocation!.longitude,
          isAdmin: _isAdmin, updatedAt: DateTime.now(),
          batteryLevel: _myBattery, status: _myStatus,
        );
      });
    }
    try {
      await _supabase.from('tac_users').upsert({
        'id': _userId, 'mission_code': _missionCode,
        'callsign': _callsign,
        'lat': _myLocation!.latitude, 'lng': _myLocation!.longitude,
        'is_admin': _isAdmin,
        'updated_at': DateTime.now().toIso8601String(),
        'battery_level': _myBattery,
        'status': _myStatus,
      });
    } catch (_) {}
    // Write breadcrumb every 3rd publish (~30 s)
    _breadcrumbTick++;
    if (_breadcrumbTick % 3 == 0) {
      final pt = _myLocation!;
      final trail = _breadcrumbs.putIfAbsent(_userId, () => []);
      trail.add(pt);
      if (trail.length > 60) trail.removeAt(0);
      try {
        await _supabase.from('tac_breadcrumbs').insert({
          'user_id': _userId, 'callsign': _callsign,
          'mission_code': _missionCode,
          'lat': pt.latitude, 'lng': pt.longitude,
        });
      } catch (_) {}
    }
  }

  void _subscribeRealtime() {
    _realtimeChannel = _supabase
        .channel('tac_${_missionCode}_$_userId')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_users',
            // No filter — receive all users across all missions
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _users.remove(id));
              } else {
                final u = TacUser.fromMap(payload.newRecord);
                // Never downgrade a fresh optimistic entry with a stale parsed one.
                final existing = _users[u.id];
                if (existing == null || u.updatedAt.isAfter(existing.updatedAt)) {
                  setState(() => _users[u.id] = u);
                }
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_markers',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'mission_code',
                value: _missionCode),
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _markers.remove(id));
              } else {
                final m = TacMarker.fromMap(payload.newRecord);
                setState(() => _markers[m.id] = m);
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_zones',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'mission_code',
                value: _missionCode),
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _zones.removeWhere((z) => z.id == id));
              } else {
                final z = TacZone.fromMap(payload.newRecord);
                setState(() {
                  _zones.removeWhere((x) => x.id == z.id);
                  _zones.add(z);
                });
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_sos',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'mission_code',
                value: _missionCode),
            callback: (payload) {
              if (!mounted) return;
              final updated = TacSosEvent.fromMap(payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord);
              setState(() {
                _activeSos.removeWhere((s) => s.id == updated.id);
                if (!updated.resolved) _activeSos.add(updated);
              });
              if (!updated.resolved && updated.userId != _userId) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('🚨 SOS from ${updated.callsign}!'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 10),
                ));
              }
            })
        .subscribe();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadInitialData());
  }

  Future<void> _loadInitialData() async {
    // Load users first — silent fail is acceptable
    try {
      final users = await _supabase.from('tac_users').select();
      if (!mounted) return;
      setState(() {
        for (final r in users as List) {
          final u = TacUser.fromMap(r as Map<String, dynamic>);
          // Never replace a fresher in-memory entry (e.g. optimistic update)
          // with a staler database row — this prevents the periodic 30-sec
          // refresh from flickering icons off the map.
          final existing = _users[u.id];
          if (existing == null || u.updatedAt.isAfter(existing.updatedAt)) {
            _users[u.id] = u;
          }
        }
      });
    } catch (_) {}

    // Load markers separately so a missing table is visible
    try {
      final markers = await _supabase
          .from('tac_markers')
          .select()
          .eq('mission_code', _missionCode);
      if (!mounted) return;
      setState(() {
        for (final r in markers as List) {
          final m = TacMarker.fromMap(r as Map<String, dynamic>);
          _markers[m.id] = m;
        }
      });
      _markerTableWarned = false;
    } catch (e) {
      if (!mounted || _markerTableWarned) return;
      _markerTableWarned = true;
      final msg = _isMarkerTableMissing(e)
          ? 'tac_markers table not found — open Tac Map Settings and re-run the setup SQL'
          : 'Could not load markers: ${e is PostgrestException ? e.message : e}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: Colors.orange,
        duration: const Duration(seconds: 8),
      ));
    }

    // Zones
    try {
      final zoneRows = await _supabase.from('tac_zones').select()
          .eq('mission_code', _missionCode) as List;
      if (!mounted) return;
      setState(() {
        _zones.clear();
        _zones.addAll(zoneRows.map((r) => TacZone.fromMap(r as Map<String, dynamic>)));
      });
    } catch (_) {}

    // Active SOS
    try {
      final sosRows = await _supabase.from('tac_sos').select()
          .eq('mission_code', _missionCode)
          .filter('resolved_at', 'is', null) as List;
      if (!mounted) return;
      setState(() {
        _activeSos.clear();
        _activeSos.addAll(sosRows.map((r) => TacSosEvent.fromMap(r as Map<String, dynamic>)));
      });
    } catch (_) {}

    // Breadcrumbs for this mission (last 200 points per user)
    try {
      final crumbRows = await _supabase.from('tac_breadcrumbs').select()
          .eq('mission_code', _missionCode)
          .order('recorded_at', ascending: true)
          .limit(500) as List;
      if (!mounted) return;
      final newCrumbs = <String, List<LatLng>>{};
      for (final r in crumbRows) {
        final uid = r['user_id'] as String;
        newCrumbs.putIfAbsent(uid, () => [])
            .add(LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble()));
      }
      setState(() {
        for (final e in newCrumbs.entries) {
          _breadcrumbs[e.key] = e.value;
        }
      });
    } catch (_) {}
  }

  static bool _isMarkerTableMissing(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    return code == '42P01' || code == 'PGRST204' ||
        msg.contains('tac_markers') || msg.contains('does not exist');
  }

  Future<void> _placeMarker(LatLng pos, TacMarkerType type) async {
    // Show immediately — don't wait for Supabase round-trip
    final tempId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _markers[tempId] = TacMarker(
        id: tempId,
        type: type,
        label: '',
        lat: pos.latitude,
        lng: pos.longitude,
        placedBy: _callsign,
        createdAt: DateTime.now(),
      );
      _placingType = null;
    });
    try {
      await _supabase.from('tac_markers').insert({
        'mission_code': _missionCode,
        'type': type.name,
        'label': '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'placed_by': _callsign,
      });
      // Real marker arrives via realtime; remove temp
      if (mounted) setState(() => _markers.remove(tempId));
    } catch (e) {
      if (!mounted) return;
      final msg = _isMarkerTableMissing(e)
          ? 'tac_markers table not found — open Tac Map Settings and re-run the setup SQL in your Supabase project'
          : 'Marker saved locally — sync failed (${e is PostgrestException ? e.message : e})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 6),
      ));
      // Keep temp marker visible locally even though sync failed
    }
  }

  Future<void> _deleteMarker(String id) async {
    try { await _supabase.from('tac_markers').delete().eq('id', id); } catch (_) {}
  }

  // ── SOS ───────────────────────────────────────────────────────────────────
  Future<void> _triggerSos() async {
    if (_myLocation == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red[900],
        title: const Text('🚨 Send SOS?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will alert ALL team members immediately.',
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SEND SOS')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _supabase.from('tac_sos').insert({
        'user_id': _userId, 'callsign': _callsign,
        'mission_code': _missionCode,
        'lat': _myLocation!.latitude, 'lng': _myLocation!.longitude,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOS failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _resolveSos(String sosId) async {
    try {
      await _supabase.from('tac_sos').update({
        'resolved_at': DateTime.now().toIso8601String(),
        'resolved_by': _callsign,
      }).eq('id', sosId);
      setState(() => _activeSos.removeWhere((s) => s.id == sosId));
    } catch (_) {}
  }

  // ── Zones ─────────────────────────────────────────────────────────────────
  void _startZonePlacement() {
    setState(() => _placingZone = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tap the map to place zone centre'),
      duration: Duration(seconds: 5),
    ));
  }

  Future<void> _createZone(LatLng pos) async {
    setState(() => _placingZone = false);
    String? name; String zoneType = 'LZ'; double radiusM = 100;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: const Text('Add Zone'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Zone name', border: OutlineInputBorder()),
            onChanged: (v) => name = v.trim(),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: zoneType,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: _kZoneTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => ss(() => zoneType = v ?? 'LZ'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: '100',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Radius (metres)', border: OutlineInputBorder()),
            onChanged: (v) => radiusM = double.tryParse(v) ?? 100,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      )),
    );
    if (result != true || name == null || name!.isEmpty) return;
    try {
      await _supabase.from('tac_zones').insert({
        'mission_code': _missionCode, 'name': name,
        'zone_type': zoneType, 'lat': pos.latitude, 'lng': pos.longitude,
        'radius_m': radiusM, 'created_by': _callsign,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zone create failed: $e')));
    }
  }

  Future<void> _deleteZone(TacZone zone) async {
    try {
      await _supabase.from('tac_zones').delete().eq('id', zone.id);
      setState(() => _zones.remove(zone));
    } catch (_) {}
  }

  // ── Status ────────────────────────────────────────────────────────────────
  void _pickStatus() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('My Check-in Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const Divider(height: 1),
          ..._kStatuses.map((s) => ListTile(
            leading: CircleAvatar(
              radius: 10,
              backgroundColor: _statusColor(s),
            ),
            title: Text(s),
            selected: _myStatus == s,
            onTap: () {
              Navigator.pop(context);
              setState(() => _myStatus = s);
              _publishLocation(); // push update immediately
            },
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Waypoint ──────────────────────────────────────────────────────────────
  Future<void> _placeWaypoint(LatLng pos) async {
    String? label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Name this waypoint'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Waypoint name', border: OutlineInputBorder()),
          onChanged: (v) => label = v.trim(),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Place')),
        ],
      ),
    );
    if (ok != true) return;
    final tempId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    final wpLabel = label?.isNotEmpty == true ? label! : 'WP';
    setState(() {
      _markers[tempId] = TacMarker(
        id: tempId, type: TacMarkerType.waypoint, label: wpLabel,
        lat: pos.latitude, lng: pos.longitude,
        placedBy: _callsign, createdAt: DateTime.now(),
      );
      _placingType = null;
    });
    try {
      await _supabase.from('tac_markers').insert({
        'mission_code': _missionCode, 'type': TacMarkerType.waypoint.name,
        'label': wpLabel, 'lat': pos.latitude, 'lng': pos.longitude,
        'placed_by': _callsign,
      });
      if (mounted) setState(() => _markers.remove(tempId));
    } catch (_) {}
  }

  Future<void> _leaveMission() async {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    try {
      await _supabase.from('tac_users').delete().eq('id', _userId);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCallsign);
    await prefs.remove(_kMissionCode);
    await prefs.remove(_kIsAdmin);
    if (mounted) {
      setState(() {
        _callsign = '';
        _missionCode = '';
        _isAdmin = false;
        _hasMission = false;
        _users.clear();
        _markers.clear();
      });
    }
  }

  void _clearRoutes() {
    setState(() => _breadcrumbs.clear());
    try {
      _supabase.from('tac_breadcrumbs')
          .delete()
          .eq('user_id', _userId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _takChannel?.unsubscribe();
    super.dispose();
  }

  // ── TAK position markers ──────────────────────────────────────────────────
  List<Marker> _buildTakMarkers() {
    return _takPositions.values.map((p) {
      final age = DateTime.now().difference(p.lastUpdated);
      final stale = age.inMinutes > 5;
      final color = stale ? Colors.white24 : p.statusColor;
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 90,
        height: 64,
        child: GestureDetector(
          onTap: () => _showTakSheet(p),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 86),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color, width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(p.callsign,
                    textAlign: TextAlign.center, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 9,
                        fontWeight: FontWeight.bold)),
                Text(_fmtTakTime(p.lastUpdated),
                    style: TextStyle(
                        color: color.withValues(alpha: 0.7), fontSize: 7)),
              ]),
            ),
            Icon(Icons.navigation, color: color, size: 28,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
          ]),
        ),
      );
    }).toList();
  }

  // ── POI markers ───────────────────────────────────────────────────────────
  List<Marker> _buildPoiMarkers() {
    return _pois.map((poi) => Marker(
      point: LatLng(poi.lat, poi.lng),
      width: 70,
      height: 58,
      child: GestureDetector(
        onTap: () => _showPoiSheet(poi),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 66),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: poi.color, width: 1),
            ),
            child: Text(poi.name,
                textAlign: TextAlign.center, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: poi.color, fontSize: 8,
                    fontWeight: FontWeight.w600)),
          ),
          Icon(poi.icon, color: poi.color, size: 26,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 4)]),
        ]),
      ),
    )).toList();
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];
    final now = DateTime.now();
    final staleThreshold = now.subtract(const Duration(minutes: 15));

    // ── User location pins ────────────────────────────────────────────────
    for (final user in _users.values) {
      if (user.updatedAt.isBefore(staleThreshold)) continue;
      if (!_showAllMissions && user.missionCode != _missionCode && user.id != _userId) continue;
      final isMe = user.id == _userId;
      final sameMission = user.missionCode == _missionCode;
      final statusCol = _statusColor(user.status);
      final baseColor = isMe ? Colors.teal : sameMission ? Colors.blue : Colors.deepOrange;
      final minutesAgo = now.difference(user.updatedAt).inMinutes;
      final timeLabel = minutesAgo < 1 ? 'now' : '${minutesAgo}m';
      final battLabel = user.batteryLevel != null ? '🔋${user.batteryLevel}%' : '';
      // SOS highlight
      final hasSos = _activeSos.any((s) => s.userId == user.id);
      markers.add(Marker(
        point: LatLng(user.lat, user.lng),
        width: 100,
        height: hasSos ? 82 : 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hasSos)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('🚨 SOS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            Container(
              constraints: const BoxConstraints(maxWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: hasSos ? Colors.red : baseColor,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: statusCol, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1,1))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(user.callsign,
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                if (battLabel.isNotEmpty || timeLabel.isNotEmpty)
                  Text('$battLabel${battLabel.isNotEmpty && timeLabel.isNotEmpty ? ' · ' : ''}$timeLabel',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 8)),
                if (user.status != 'Active')
                  Text(user.status,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: statusCol == Colors.teal ? Colors.white : statusCol,
                          fontSize: 7, fontWeight: FontWeight.w600)),
              ]),
            ),
            Icon(isMe ? Icons.person_pin : Icons.person_pin_circle,
                color: hasSos ? Colors.red : baseColor, size: 32,
                shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
          ],
        ),
      ));
    }

    // ── Zone labels ───────────────────────────────────────────────────────
    for (final zone in _zones) {
      markers.add(Marker(
        point: LatLng(zone.lat, zone.lng),
        width: 90, height: 24,
        child: GestureDetector(
          onLongPress: _isAdmin ? () => _confirmDeleteZone(zone) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: zone.color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(zone.name,
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ),
      ));
    }

    // ── Tac markers (patient, exfil, waypoints) ───────────────────────────
    for (final m in _markers.values) {
      markers.add(Marker(
        point: LatLng(m.lat, m.lng),
        width: m.type == TacMarkerType.waypoint ? 72 : 48,
        height: m.type == TacMarkerType.waypoint ? 56 : 48,
        child: GestureDetector(
          onLongPress: () => _confirmDeleteMarker(m),
          child: m.type == TacMarkerType.waypoint
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: TacMarkerType.waypoint.color, borderRadius: BorderRadius.circular(4)),
                    child: Text(m.label.isNotEmpty ? m.label : 'WP',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  Icon(TacMarkerType.waypoint.icon, color: TacMarkerType.waypoint.color, size: 28,
                      shadows: const [Shadow(color: Colors.black45, blurRadius: 3)]),
                ])
              : Icon(m.type.icon, color: m.type.color, size: 40,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
        ),
      ));
    }

    return markers;
  }

  void _confirmDeleteZone(TacZone zone) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Zone?'),
        content: Text('Remove "${zone.name}" (${zone.zoneType})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { Navigator.pop(context); _deleteZone(zone); },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  LatLng? _extractionStart() {
    for (final m in _markers.values) {
      if (m.type == TacMarkerType.extractionStart) return LatLng(m.lat, m.lng);
    }
    return null;
  }

  LatLng? _extractionEnd() {
    for (final m in _markers.values) {
      if (m.type == TacMarkerType.extractionEnd) return LatLng(m.lat, m.lng);
    }
    return null;
  }

  void _confirmDeleteMarker(TacMarker m) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Marker?'),
        content: Text('${m.type.label} placed by ${m.placedBy}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMarker(m.id);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg  = Color(0xFF0D1117);
    const dim = Color(0xFF8B949E);
    const cyan = Colors.cyanAccent;

    // ── Polylines: exfil route + breadcrumb trails ─────────────────────────
    final polylines = <Polyline>[];
    final extractStart = _extractionStart();
    final extractEnd   = _extractionEnd();
    if (extractStart != null && extractEnd != null) {
      polylines.add(Polyline(points: [extractStart, extractEnd],
          color: Colors.orange, strokeWidth: 3));
    }
    if (_showTrails) {
      final trailColors = [Colors.teal, Colors.blue, Colors.deepOrange,
                           Colors.purple, Colors.green, Colors.amber];
      var ci = 0;
      for (final entry in _breadcrumbs.entries) {
        if (entry.value.length < 2) continue;
        polylines.add(Polyline(points: entry.value,
            color: trailColors[ci % trailColors.length].withValues(alpha: 0.55),
            strokeWidth: 2.5));
        ci++;
      }
    }

    // ── Zone circles ───────────────────────────────────────────────────────
    final zoneCircles = _zones.map((z) => CircleMarker(
        point: LatLng(z.lat, z.lng), radius: z.radiusM,
        useRadiusInMeter: true,
        color: z.color.withValues(alpha: 0.15),
        borderColor: z.color, borderStrokeWidth: 2.5)).toList();

    final mapCenter = _mapReady
        ? _mapCtrl.camera.center
        : (_myLocation ?? const LatLng(37.0902, -95.7129));
    final zoom = _mapReady ? _mapCtrl.camera.zoom : 14.0;

    // ── ATAK full-screen layout: no AppBar, overlay panels ────────────────
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          // ── Full-screen map ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(37.0902, -95.7129),
              initialZoom: _myLocation != null ? 14 : 4,
              onMapReady: () {
                _mapReady = true;
                if (_myLocation != null) _mapCtrl.move(_myLocation!, 14);
              },
              onPositionChanged: (_, __) => setState(() {}),
              onTap: (_, point) {
                if (_placingZone) { _createZone(point); return; }
                if (_placingType == TacMarkerType.waypoint) { _placeWaypoint(point); return; }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _baseLayer == _BaseLayer.osm
                    ? _kDarkTileUrl : _baseLayer.urlTemplate,
                userAgentPackageName: 'com.resqruck.app',
                tileProvider: _CachedTileProvider(),
                additionalOptions: const {},
              ),
              if (_incidentOverlay != null)
                OverlayImageLayer(overlayImages: [
                  OverlayImage(
                    bounds: _incidentOverlay!.bounds,
                    imageProvider: MemoryImage(_incidentOverlay!.imageBytes),
                    opacity: 0.7,
                  ),
                ]),
              PolylineLayer(polylines: polylines),
              if (zoneCircles.isNotEmpty) CircleLayer(circles: zoneCircles),
              if (_showTakLayer && _takPositions.isNotEmpty)
                MarkerLayer(markers: _buildTakMarkers()),
              if (_showPoiLayer && _pois.isNotEmpty)
                MarkerLayer(markers: _buildPoiMarkers()),
              MarkerLayer(markers: _buildMapMarkers()),
            ],
          ),

          // ── SOS alert banner ────────────────────────────────────────────
          if (_activeSos.isNotEmpty)
            Positioned(top: 0, left: 0, right: 0,
              child: Material(color: Colors.red,
                child: InkWell(
                  onTap: () => _mapCtrl.move(
                      LatLng(_activeSos.first.lat, _activeSos.first.lng), 14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(children: [
                      const Icon(Icons.sos, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '🚨 SOS — ${_activeSos.map((s) => s.callsign).join(', ')}',
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 12))),
                      if (_isAdmin)
                        TextButton(onPressed: () => _resolveSos(_activeSos.first.id),
                            child: const Text('Resolve',
                                style: TextStyle(color: Colors.white, fontSize: 11))),
                    ]),
                  ),
                )),
            ),

          // ── ATAK top header bar ─────────────────────────────────────────
          Positioned(
            top: _activeSos.isNotEmpty ? 36 : 0,
            left: 0, right: 0,
            child: Container(
              color: bg.withValues(alpha: 0.9),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(children: [
                // TAK label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: cyan.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('TAK', style: TextStyle(color: cyan,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
                const SizedBox(width: 6),
                // Mission code
                if (_hasMission)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(_missionCode,
                        style: const TextStyle(color: Colors.tealAccent,
                            fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                else
                  const Text('NO MISSION',
                      style: TextStyle(color: Colors.white30, fontSize: 9,
                          letterSpacing: 0.5)),
                const SizedBox(width: 6),
                if (_takPositions.isNotEmpty)
                  Text('${_takPositions.length} ATAK',
                      style: const TextStyle(color: cyan, fontSize: 9,
                          fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(3)),
                    child: const Text('ADMIN',
                        style: TextStyle(color: Colors.orange, fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 6),
                // GPS status
                Icon(Icons.gps_fixed, size: 11,
                    color: _myLocation != null ? Colors.greenAccent : Colors.red),
                const SizedBox(width: 3),
                Text(_myLocation != null ? 'FIX' : 'NO FIX',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                        color: _myLocation != null ? Colors.greenAccent : Colors.red)),
                if (_myBattery != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    _myBattery! > 60 ? Icons.battery_full
                        : _myBattery! > 20 ? Icons.battery_3_bar
                        : Icons.battery_alert,
                    size: 12,
                    color: _myBattery! > 20 ? Colors.white54 : Colors.redAccent),
                  Text('${_myBattery}%',
                      style: TextStyle(fontSize: 9,
                          color: _myBattery! > 20 ? Colors.white54 : Colors.redAccent)),
                ],
              ]),
            ),
          ),

          // ── Compass (ATAK style) ────────────────────────────────────────
          Positioned(
            top: (_activeSos.isNotEmpty ? 36 : 0) + 34,
            right: 52,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: bg.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12)),
              child: const Stack(alignment: Alignment.center, children: [
                Text('N', style: TextStyle(color: Colors.redAccent,
                    fontSize: 11, fontWeight: FontWeight.bold)),
                Positioned(bottom: 3,
                    child: Text('S', style: TextStyle(
                        color: Color(0xFF8B949E), fontSize: 7))),
              ]),
            ),
          ),

          // ── Zoom badge ─────────────────────────────────────────────────
          Positioned(
            top: (_activeSos.isNotEmpty ? 36 : 0) + 34,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: bg.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white10)),
              child: Text('Z${zoom.round()}',
                  style: TextStyle(color: dim, fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),

          // ── Right tool panel ────────────────────────────────────────────
          Positioned(
            right: 8,
            top: (_activeSos.isNotEmpty ? 36 : 0) + 34,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Zoom
              _atakBtn(Icons.add, bg, Colors.white70,
                  () { final z = (zoom + 1).clamp(3.0, 20.0);
                        _mapCtrl.move(_mapCtrl.camera.center, z); }),
              const SizedBox(height: 1),
              _atakBtn(Icons.remove, bg, Colors.white70,
                  () { final z = (zoom - 1).clamp(3.0, 20.0);
                        _mapCtrl.move(_mapCtrl.camera.center, z); }),
              const SizedBox(height: 6),
              // Re-centre
              _atakBtn(Icons.my_location, bg,
                  _myLocation != null ? cyan : Colors.white24,
                  () { if (_myLocation != null) _mapCtrl.move(_myLocation!, 14); }),
              const SizedBox(height: 6),
              // Layer toggles
              _atakBtn(Icons.radar, bg,
                  _showTakLayer ? cyan : Colors.white24,
                  () => setState(() => _showTakLayer = !_showTakLayer)),
              const SizedBox(height: 1),
              _atakBtn(Icons.place, bg,
                  _showPoiLayer ? Colors.orangeAccent : Colors.white24,
                  () => setState(() => _showPoiLayer = !_showPoiLayer)),
              const SizedBox(height: 1),
              _atakBtn(Icons.route, bg,
                  _showTrails ? Colors.amber : Colors.white24,
                  () => setState(() => _showTrails = !_showTrails)),
              const SizedBox(height: 6),
              // Mine / All users
              _atakBtn(
                  _showAllMissions ? Icons.people : Icons.person,
                  bg, _showAllMissions ? cyan : Colors.white38,
                  () => setState(() => _showAllMissions = !_showAllMissions)),
              const SizedBox(height: 6),
              // Location share
              _atakBtn(
                  _sharingLocation ? Icons.location_on : Icons.location_off,
                  bg, _sharingLocation ? Colors.greenAccent : Colors.redAccent,
                  _sharingLocation ? _stopSharing : _startSharing),
              const SizedBox(height: 6),
              // Wildfire overlay
              _atakBtn(Icons.local_fire_department, bg, Colors.deepOrangeAccent,
                  _showIncidentBrowser),
              const SizedBox(height: 1),
              // Tile layers picker
              _atakBtn(Icons.layers, bg, Colors.white54, _showLayerPicker),
              const SizedBox(height: 1),
              // Field tools (GPS, LZ, Offline maps)
              _atakBtn(Icons.build_outlined, bg, Colors.white54, _showFieldTools),
              const SizedBox(height: 6),
              // SOS
              _atakBtn(Icons.sos, Colors.red, Colors.white, _triggerSos),
              const SizedBox(height: 6),
              // Overflow menu
              _atakPopup(bg, dim),
            ]),
          ),

          // ── Join Mission button (when no mission) ───────────────────────
          if (!_hasMission)
            Positioned(
              bottom: 56, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _joinMission,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(
                          color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.group_add, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Join Mission', style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 14)),
                    ]),
                  ),
                ),
              ),
            ),

          // ── Marker placement overlay ────────────────────────────────────
          if (_placingType != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (!_mapReady) return;
                  final point = _mapCtrl.camera.pointToLatLng(
                      Point(details.localPosition.dx, details.localPosition.dy));
                  _placeMarker(point, _placingType!);
                },
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_placingType!.icon, color: _placingType!.color, size: 52),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                          color: _placingType!.color,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Tap to place ${_placingType!.label}',
                          style: const TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
              ),
            ),

          // ── Zone placement hint ─────────────────────────────────────────
          if (_placingZone)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (!_mapReady) return;
                  _createZone(_mapCtrl.camera.pointToLatLng(
                      Point(d.localPosition.dx, d.localPosition.dy)));
                },
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                        color: Colors.purple, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Tap to place zone centre',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),

          // ── Bottom: TEAM panel + coordinate bar ─────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_hasMission)
                _TeamPanel(
                  users: _users.values.where((u) => u.updatedAt
                      .isAfter(DateTime.now().subtract(const Duration(minutes: 15))))
                      .toList(),
                  myId: _userId,
                  missionCode: _missionCode,
                  isAdmin: _isAdmin,
                  showAll: _showAllMissions,
                  placingType: _placingType,
                  onPlaceType: (t) =>
                      setState(() => _placingType = _placingType == t ? null : t),
                  onKickUser: (id) async {
                    try { await _supabase.from('tac_users').delete().eq('id', id); }
                    catch (_) {}
                    setState(() => _users.remove(id));
                  },
                ),
              // Coordinate bar
              Container(
                color: bg.withValues(alpha: 0.9),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(children: [
                  Icon(Icons.gps_not_fixed, size: 11, color: dim),
                  const SizedBox(width: 5),
                  Text(
                    '${mapCenter.latitude.toStringAsFixed(5)},  '
                    '${mapCenter.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10,
                        fontFamily: 'monospace')),
                  const Spacer(),
                  if (_myStatus != 'Active')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: _statusColor(_myStatus).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3)),
                      child: Text(_myStatus,
                          style: TextStyle(color: _statusColor(_myStatus),
                              fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Compact ATAK-style square tool button.
  Widget _atakBtn(IconData icon, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white10)),
          child: Icon(icon, color: fg, size: 17),
        ),
      );

  /// Overflow ⋮ popup menu — all secondary actions.
  Widget _atakPopup(Color bg, Color fg) {
    return PopupMenuButton<String>(
      icon: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white10)),
        child: Icon(Icons.more_vert, color: fg, size: 17),
      ),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        if (_hasMission)
          const PopupMenuItem(value: 'leave',    child: Text('Leave Mission')),
        const PopupMenuItem(value: 'join',        child: Text('Join / Change Mission')),
        const PopupMenuItem(value: 'recenter',    child: Text('Re-centre')),
        const PopupMenuItem(value: 'status',      child: Text('My Check-in Status')),
        const PopupMenuItem(value: 'clear_routes',child: Text('Clear Routes')),
        if (_isAdmin)
          const PopupMenuItem(value: 'add_zone',  child: Text('Add Zone')),
        const PopupMenuItem(value: 'settings',    child: Text('Supabase Settings')),
        if (_incidentOverlay != null)
          const PopupMenuItem(value: 'clear_overlay', child: Text('Clear Fire Overlay')),
        const PopupMenuItem(value: 'clear_patient',    child: Text('Clear Patient Marker')),
        const PopupMenuItem(value: 'clear_exfil_start',child: Text('Clear Exfil Start')),
        const PopupMenuItem(value: 'clear_exfil_end',  child: Text('Clear Exfil End')),
      ],
      onSelected: (v) async {
        if (v == 'leave')             _leaveMission();
        if (v == 'join')              _joinMission();
        if (v == 'recenter' && _myLocation != null)
          _mapCtrl.move(_myLocation!, 14);
        if (v == 'status')            _pickStatus();
        if (v == 'clear_routes')      _clearRoutes();
        if (v == 'add_zone')          _startZonePlacement();
        if (v == 'clear_overlay')     setState(() => _incidentOverlay = null);
        if (v == 'clear_patient')     _clearMarkersByType(TacMarkerType.patient);
        if (v == 'clear_exfil_start') _clearMarkersByType(TacMarkerType.extractionStart);
        if (v == 'clear_exfil_end')   _clearMarkersByType(TacMarkerType.extractionEnd);
        if (v == 'settings') {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => _SupabaseConfigScreen(onSaved: () => Navigator.pop(context))));
        }
      },
    );
  }

  void _showFieldTools() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Field Tools',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gps_fixed, color: Colors.blue),
            title: const Text('GPS Tools'),
            subtitle: const Text('Coordinates, what3words, saved locations'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GpsToolsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined, color: Colors.brown),
            title: const Text('Offline Maps'),
            subtitle: const Text('Download and manage offline tiles'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const OfflineMapsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined, color: Colors.amber),
            title: const Text('Sun & Weather'),
            subtitle: const Text('Sunrise/sunset, weather forecast'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SunWeatherScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.flight_land, color: Colors.cyan),
            title: const Text('LZ Assessment'),
            subtitle: const Text('Landing zone safety evaluation'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LzAssessmentScreen()));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showLayerPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Base Map Layer', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._BaseLayer.values.map((layer) => ListTile(
                  title: Text(layer.label),
                  leading: Icon(
                    _baseLayer == layer
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () {
                    setState(() => _baseLayer = layer);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showIncidentBrowser() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => _IncidentBrowser(
          scrollController: ctrl,
          onLoad: (url, name) {
            Navigator.pop(context);
            _loadKmz(url, name);
          },
        ),
      ),
    );
  }

  Future<void> _loadKmz(String url, String name) async {
    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(SnackBar(
        content: Text('Downloading $name…'),
        duration: const Duration(seconds: 30)));
    try {
      final client = _wildfireClient();
      final resp = await client.get(Uri.parse(url));
      client.close();
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final archive = ZipDecoder().decodeBytes(resp.bodyBytes);

      String? kmlContent;
      Uint8List? imgBytes;

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final n = file.name.toLowerCase();
        if (n.endsWith('.kml') && kmlContent == null) {
          kmlContent = String.fromCharCodes(file.content as List<int>);
        } else if ((n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg')) &&
            imgBytes == null) {
          imgBytes = Uint8List.fromList(file.content as List<int>);
        }
      }

      if (kmlContent == null) throw Exception('No KML found in KMZ');

      // Look up the overlay image via href if we didn't find one by extension
      if (imgBytes == null) {
        final hrefMatch = RegExp(r'<href>(.*?)</href>').firstMatch(kmlContent);
        if (hrefMatch != null) {
          final hrefName = hrefMatch.group(1)?.trim();
          for (final file in archive.files) {
            if (file.isFile && file.name == hrefName) {
              imgBytes = Uint8List.fromList(file.content as List<int>);
              break;
            }
          }
        }
      }

      final northM = RegExp(r'<north>\s*([\d.\-]+)\s*</north>').firstMatch(kmlContent);
      final southM = RegExp(r'<south>\s*([\d.\-]+)\s*</south>').firstMatch(kmlContent);
      final eastM  = RegExp(r'<east>\s*([\d.\-]+)\s*</east>').firstMatch(kmlContent);
      final westM  = RegExp(r'<west>\s*([\d.\-]+)\s*</west>').firstMatch(kmlContent);

      final north = double.tryParse(northM?.group(1) ?? '');
      final south = double.tryParse(southM?.group(1) ?? '');
      final east  = double.tryParse(eastM?.group(1)  ?? '');
      final west  = double.tryParse(westM?.group(1)  ?? '');

      if (north == null || south == null || east == null || west == null) {
        throw Exception('Could not parse map bounds from KML');
      }
      if (imgBytes == null) throw Exception('No overlay image found in KMZ');

      final bounds = LatLngBounds(LatLng(south, west), LatLng(north, east));

      if (mounted) {
        snack.hideCurrentSnackBar();
        setState(() => _incidentOverlay =
            _IncidentOverlay(name: name, imageBytes: imgBytes!, bounds: bounds));
        _mapCtrl.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(16)));
        snack.showSnackBar(SnackBar(
            content: Text('Loaded: $name'),
            duration: const Duration(seconds: 3)));
      }
    } catch (e) {
      if (mounted) {
        snack.hideCurrentSnackBar();
        snack.showSnackBar(SnackBar(
            content: Text('Failed to load KMZ: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4)));
      }
    }
  }
}

class _TeamPanel extends StatefulWidget {
  final List<TacUser> users;
  final String myId;
  final String missionCode;
  final bool isAdmin;
  final bool showAll;
  final TacMarkerType? placingType;
  final ValueChanged<TacMarkerType> onPlaceType;
  final ValueChanged<String> onKickUser;

  const _TeamPanel({
    required this.users,
    required this.myId,
    required this.missionCode,
    required this.isAdmin,
    required this.showAll,
    required this.placingType,
    required this.onPlaceType,
    required this.onKickUser,
  });

  @override
  State<_TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends State<_TeamPanel> {
  @override
  Widget build(BuildContext context) {
    final visibleUsers = widget.showAll
        ? widget.users
        : widget.users.where((u) => u.missionCode == widget.missionCode).toList();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              widget.showAll ? 'ALL MISSIONS' : 'TEAM — ${widget.missionCode}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: visibleUsers.isEmpty
                      ? [const Text('No members', style: TextStyle(fontSize: 11, color: Colors.grey))]
                      : visibleUsers.map((u) {
                          final isMe = u.id == widget.myId;
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: widget.isAdmin && !isMe
                                ? GestureDetector(
                                    onLongPress: () => _confirmKick(u),
                                    child: _userChip(u, isMe),
                                  )
                                : _userChip(u, isMe),
                          );
                        }).toList(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Text('PLACE:', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: TacMarkerType.values.map((t) {
                    // Waypoint placement is handled separately (needs name dialog)
                    final active = widget.placingType == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.icon, size: 14, color: active ? Colors.white : t.color),
                          const SizedBox(width: 4),
                          Text(t.label,
                              style: TextStyle(fontSize: 11, color: active ? Colors.white : null)),
                        ]),
                        selected: active,
                        onSelected: (_) => widget.onPlaceType(t),
                        selectedColor: t.color,
                        checkmarkColor: Colors.white,
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
          if (widget.placingType != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tap the map to place ${widget.placingType!.label} marker. Tap chip again to cancel.',
                style: TextStyle(fontSize: 11, color: widget.placingType!.color, fontStyle: FontStyle.italic),
              ),
            ),
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Admin: long-press a name to remove from map',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _userChip(TacUser u, bool isMe) {
    final label = widget.showAll && u.missionCode != widget.missionCode
        ? '${u.callsign} (${u.missionCode})'
        : u.callsign;
    return Chip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white : null,
              fontWeight: isMe ? FontWeight.bold : null)),
      backgroundColor: isMe ? Colors.teal : null,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _confirmKick(TacUser u) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove from Map?'),
        content: Text('Remove ${u.callsign} from the active map?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { Navigator.pop(context); widget.onKickUser(u.id); },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _IncidentEntry {
  final String name;
  final String url;
  final bool isDirectory;
  const _IncidentEntry(
      {required this.name, required this.url, required this.isDirectory});
}

class _IncidentBrowser extends StatefulWidget {
  final ScrollController scrollController;
  final void Function(String url, String name) onLoad;

  const _IncidentBrowser(
      {required this.scrollController, required this.onLoad});

  @override
  State<_IncidentBrowser> createState() => _IncidentBrowserState();
}

class _IncidentBrowserState extends State<_IncidentBrowser> {
  static const _rootUrl =
      'https://ftp.wildfire.gov/public/incident_specific_maps/';

  List<_IncidentEntry>? _entries;
  String? _error;
  String _currentUrl = _rootUrl;
  final List<String> _breadcrumbs = [_rootUrl];

  @override
  void initState() {
    super.initState();
    _fetchDirectory(_rootUrl);
  }

  Future<void> _fetchDirectory(String url) async {
    if (mounted) setState(() { _entries = null; _error = null; });
    try {
      final client = _wildfireClient();
      final resp = await client.get(Uri.parse(url));
      client.close();
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final parsed = _parseApacheIndex(resp.body, url);
      if (mounted) setState(() { _entries = parsed; _currentUrl = url; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<_IncidentEntry> _parseApacheIndex(String html, String baseUrl) {
    final entries = <_IncidentEntry>[];
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final pattern = RegExp(r'href="([^"?#][^"]*?)"', caseSensitive: false);
    for (final m in pattern.allMatches(html)) {
      final href = m.group(1)!;
      if (href.startsWith('..') || href.startsWith('/')) continue;
      final isDir = href.endsWith('/');
      final isKmz = href.toLowerCase().endsWith('.kmz');
      if (!isDir && !isKmz) continue;
      entries.add(_IncidentEntry(
        name: Uri.decodeComponent(href.replaceAll('/', '')),
        url: '$base$href',
        isDirectory: isDir,
      ));
    }
    return entries;
  }

  void _navigate(String url) {
    _breadcrumbs.add(url);
    _fetchDirectory(url);
  }

  void _back() {
    if (_breadcrumbs.length > 1) {
      _breadcrumbs.removeLast();
      _fetchDirectory(_breadcrumbs.last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _currentUrl.length > _rootUrl.length
        ? _currentUrl.substring(_rootUrl.length)
        : '';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          child: Row(
            children: [
              if (_breadcrumbs.length > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text('Wildfire Incident Maps',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _fetchDirectory(_currentUrl),
              ),
            ],
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
            ),
          ),
        const Divider(height: 8),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : _entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : _entries!.isEmpty
                      ? const Center(
                          child: Text('No maps or subdirectories found.'))
                      : ListView.builder(
                          controller: widget.scrollController,
                          itemCount: _entries!.length,
                          itemBuilder: (_, i) {
                            final e = _entries![i];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                e.isDirectory ? Icons.folder : Icons.map,
                                color: e.isDirectory
                                    ? Colors.amber
                                    : Colors.green,
                              ),
                              title: Text(e.name,
                                  style: const TextStyle(fontSize: 13)),
                              trailing: e.isDirectory
                                  ? const Icon(Icons.chevron_right)
                                  : FilledButton.tonal(
                                      onPressed: () =>
                                          widget.onLoad(e.url, e.name),
                                      child: const Text('Load'),
                                    ),
                              onTap: e.isDirectory
                                  ? () => _navigate(e.url)
                                  : null,
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
