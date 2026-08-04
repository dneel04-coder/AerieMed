import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../tac_map.dart' show TacUser, TacZone, TacMarker, TacSosEvent;
import 'incident_service.dart';
import 'no_incident_placeholder.dart';

const _kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Live personnel + static markers/zones for the active incident's
/// mission_code, on a genuinely desktop-sized map canvas (full window
/// height, not a letterboxed phone screen).
class LiveMapScreen extends StatefulWidget {
  final TacIncident? incident;
  const LiveMapScreen({super.key, required this.incident});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _mapCtrl = MapController();
  final Map<String, TacUser> _users = {};
  final Map<String, TacZone> _zones = {};
  final Map<String, TacMarker> _markers = {};
  final Map<String, TacSosEvent> _sos = {};
  RealtimeChannel? _channel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant LiveMapScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.missionCode != widget.incident?.missionCode) _bind();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _bind() async {
    _channel?.unsubscribe();
    _users.clear();
    _zones.clear();
    _markers.clear();
    _sos.clear();
    final incident = widget.incident;
    if (incident == null) return;
    setState(() => _loading = true);

    final client = SupabaseService.client;
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final mission = incident.missionCode;

    try {
      final users = await client.from('tac_users').select().eq('mission_code', mission) as List;
      for (final r in users) {
        final u = TacUser.fromMap(r as Map<String, dynamic>);
        _users[u.id] = u;
      }
      final zones = await client.from('tac_zones').select().eq('mission_code', mission) as List;
      for (final r in zones) {
        final z = TacZone.fromMap(r as Map<String, dynamic>);
        _zones[z.id] = z;
      }
      final markers = await client.from('tac_markers').select().eq('mission_code', mission) as List;
      for (final r in markers) {
        final m = TacMarker.fromMap(r as Map<String, dynamic>);
        _markers[m.id] = m;
      }
      final sos = await client.from('tac_sos').select().eq('mission_code', mission) as List;
      for (final r in sos) {
        final s = TacSosEvent.fromMap(r as Map<String, dynamic>);
        if (!s.resolved) _sos[s.id] = s;
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
    _fitToMarkers();

    _channel = client
        .channel('admin_console_$mission')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_users',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _users.remove(id));
              } else {
                final u = TacUser.fromMap(payload.newRecord);
                setState(() => _users[u.id] = u);
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_zones',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _zones.remove(id));
              } else {
                final z = TacZone.fromMap(payload.newRecord);
                setState(() => _zones[z.id] = z);
              }
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tac_markers',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
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
            table: 'tac_sos',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
            callback: (payload) {
              if (!mounted) return;
              if (payload.eventType == PostgresChangeEvent.delete) {
                final id = payload.oldRecord['id'] as String?;
                if (id != null) setState(() => _sos.remove(id));
              } else {
                final s = TacSosEvent.fromMap(payload.newRecord);
                setState(() {
                  if (s.resolved) {
                    _sos.remove(s.id);
                  } else {
                    _sos[s.id] = s;
                  }
                });
              }
            })
        .subscribe();
  }

  void _fitToMarkers() {
    final points = [
      ..._users.values.map((u) => LatLng(u.lat, u.lng)),
      ..._markers.values.map((m) => LatLng(m.lat, m.lng)),
    ];
    if (points.isEmpty) return;
    try {
      _mapCtrl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(60),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incident == null) {
      return const NoIncidentPlaceholder(feature: 'the Live Map');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    final center = _users.isNotEmpty
        ? LatLng(_users.values.first.lat, _users.values.first.lng)
        : const LatLng(39.8283, -98.5795); // continental US fallback

    return Row(
      children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: center, initialZoom: _users.isEmpty ? 4 : 13),
              children: [
                TileLayer(urlTemplate: _kOsmTileUrl, userAgentPackageName: 'com.peninsulathreat.resqruck'),
                CircleLayer(
                  circles: _zones.values
                      .map((z) => CircleMarker(
                            point: LatLng(z.lat, z.lng),
                            radius: z.radiusM,
                            useRadiusInMeter: true,
                            color: z.color.withValues(alpha: 0.15),
                            borderColor: z.color,
                            borderStrokeWidth: 2,
                          ))
                      .toList(),
                ),
                MarkerLayer(markers: [
                  ..._markers.values.map((m) => Marker(
                        point: LatLng(m.lat, m.lng),
                        width: 36,
                        height: 36,
                        child: Icon(m.type.icon, color: m.type.color, size: 28),
                      )),
                  ..._sos.values.map((s) => Marker(
                        point: LatLng(s.lat, s.lng),
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.emergency, color: Colors.red, size: 36),
                      )),
                  ..._users.values.map((u) => Marker(
                        point: LatLng(u.lat, u.lng),
                        width: 120,
                        height: 56,
                        child: _UserMarker(user: u),
                      )),
                ]),
              ],
            ),
            Positioned(
              right: 12,
              top: 12,
              child: FloatingActionButton.small(
                heroTag: 'fit_map',
                onPressed: _fitToMarkers,
                tooltip: 'Fit to markers',
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ]),
        ),
        SizedBox(
          width: 260,
          child: Material(
            elevation: 1,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('On map (${_users.length})', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ..._users.values.map((u) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle, size: 12, color: Colors.green),
                      title: Text(u.callsign),
                      subtitle: Text('${u.status} • ${u.batteryLevel ?? '—'}%'),
                    )),
                if (_sos.isNotEmpty) ...[
                  const Divider(),
                  Text('Active SOS (${_sos.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.red)),
                  const SizedBox(height: 8),
                  ..._sos.values.map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.emergency, color: Colors.red, size: 18),
                        title: Text(s.callsign),
                      )),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UserMarker extends StatelessWidget {
  final TacUser user;
  const _UserMarker({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(user.callsign, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ),
      const Icon(Icons.person_pin_circle, color: Colors.teal, size: 32),
    ]);
  }
}
