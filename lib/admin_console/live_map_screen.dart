import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../tac_map.dart'
    show TacUser, TacZone, TacMarker, TacSosEvent, resourceTypeIcon, parseHexColor, showPersonnelInfoSheet;
import '../incident_service.dart';

const _kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

// A device publishes every ~10s while sharing location — anything older than
// this is treated as not currently transmitting rather than "their last
// known spot" (tac_users has no TTL of its own; see joinMissionSilently for
// the related fix to stop old-mission rows from lingering in the first place).
const _kCurrentWindow = Duration(minutes: 5);

enum _MapMode { allUsers, thisIncident }

/// Live personnel + static markers/zones, either scoped to the active
/// incident's mission_code or — with no incident required — everyone across
/// every mission, on a genuinely desktop-sized map canvas.
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
  final Map<String, String> _resourceTypeByUser = {};
  final Map<String, Color> _teamColorByUser = {};
  final Map<String, String> _teamNameByUser = {};
  final Map<String, String> _deploymentStatusByUser = {};
  RealtimeChannel? _channel;
  bool _loading = true;
  late _MapMode _mode;
  Timer? _agingTimer;

  @override
  void initState() {
    super.initState();
    _mode = widget.incident == null ? _MapMode.allUsers : _MapMode.thisIncident;
    _bind();
    // _users doesn't change on its own between publishes, but "is this still
    // current" does as time passes — re-render periodically so a marker
    // actually disappears once its owner stops transmitting, rather than
    // only when the next unrelated update happens to trigger a rebuild.
    _agingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LiveMapScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.missionCode != widget.incident?.missionCode) {
      if (widget.incident == null) _mode = _MapMode.allUsers;
      _bind();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _agingTimer?.cancel();
    super.dispose();
  }

  bool _isCurrent(TacUser u) => DateTime.now().toUtc().difference(u.updatedAt.toUtc()) < _kCurrentWindow;

  Iterable<TacUser> get _visibleUsers => _users.values.where(_isCurrent);

  Future<void> _resolveSos(TacSosEvent s) async {
    setState(() => _sos.remove(s.id)); // optimistic — realtime confirms shortly after
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('tac_sos').update({
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'resolved_by': 'Command Console',
      }).eq('id', s.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resolve SOS: $e')));
      }
    }
  }

  void _setMode(_MapMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _bind();
  }

  /// Null when in "all users" mode — every fetch/subscription below is
  /// unfiltered (every mission) whenever this is null.
  String? get _missionFilter => _mode == _MapMode.thisIncident ? widget.incident?.missionCode : null;

  Future<void> _bind() async {
    _channel?.unsubscribe();
    _users.clear();
    _zones.clear();
    _markers.clear();
    _sos.clear();
    _resourceTypeByUser.clear();
    _teamColorByUser.clear();
    _teamNameByUser.clear();
    _deploymentStatusByUser.clear();
    if (_mode == _MapMode.thisIncident && widget.incident == null) return;
    setState(() => _loading = true);

    final client = SupabaseService.client;
    if (client == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final mission = _missionFilter;

    try {
      final userRows = mission == null
          ? await client.from('tac_users').select() as List
          : await client.from('tac_users').select().eq('mission_code', mission) as List;
      for (final r in userRows) {
        final u = TacUser.fromMap(r as Map<String, dynamic>);
        // Keyed by id, so this naturally collapses any leftover rows under a
        // different mission_code (see joinMissionSilently) — but query order
        // isn't guaranteed, so keep whichever is actually newest rather than
        // whichever happened to be processed last.
        final existing = _users[u.id];
        if (existing == null || u.updatedAt.isAfter(existing.updatedAt)) {
          _users[u.id] = u;
        }
      }
      final zoneRows = mission == null
          ? await client.from('tac_zones').select() as List
          : await client.from('tac_zones').select().eq('mission_code', mission) as List;
      for (final r in zoneRows) {
        final z = TacZone.fromMap(r as Map<String, dynamic>);
        _zones[z.id] = z;
      }
      final markerRows = mission == null
          ? await client.from('tac_markers').select() as List
          : await client.from('tac_markers').select().eq('mission_code', mission) as List;
      for (final r in markerRows) {
        final m = TacMarker.fromMap(r as Map<String, dynamic>);
        _markers[m.id] = m;
      }
      final sosRows = mission == null
          ? await client.from('tac_sos').select() as List
          : await client.from('tac_sos').select().eq('mission_code', mission) as List;
      for (final r in sosRows) {
        final s = TacSosEvent.fromMap(r as Map<String, dynamic>);
        if (!s.resolved) _sos[s.id] = s;
      }
      // Personnel role/team — separate tables from tac_users (location), so
      // resolved into lookup maps here rather than joined server-side.
      // Degrades silently (no icon/color override) if the schema migration
      // for teams/resource_type/team_id hasn't been run yet.
      final teamRows = await client.from('teams').select('id, name, color_hex') as List;
      final colorByTeam = <String, Color>{};
      final nameByTeam = <String, String>{};
      for (final r in teamRows) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        final color = parseHexColor(m['color_hex'] as String?);
        if (color != null) colorByTeam[id] = color;
        nameByTeam[id] = m['name'] as String? ?? '';
      }
      final profileRows = await client
          .from('user_profiles')
          .select('user_id, resource_type, team_id, deployment_status') as List;
      for (final r in profileRows) {
        final m = r as Map<String, dynamic>;
        final userId = m['user_id'] as String? ?? '';
        if (userId.isEmpty) continue;
        final resourceType = m['resource_type'] as String? ?? '';
        if (resourceType.isNotEmpty) _resourceTypeByUser[userId] = resourceType;
        final deploymentStatus = m['deployment_status'] as String? ?? '';
        if (deploymentStatus.isNotEmpty) _deploymentStatusByUser[userId] = deploymentStatus;
        final teamId = m['team_id'] as String?;
        if (teamId != null) {
          final teamColor = colorByTeam[teamId];
          if (teamColor != null) _teamColorByUser[userId] = teamColor;
          final teamName = nameByTeam[teamId];
          if (teamName != null && teamName.isNotEmpty) _teamNameByUser[userId] = teamName;
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
    _fitToMarkers();

    var channelBuilder = client.channel('admin_console_map_${mission ?? 'all'}');
    channelBuilder = channelBuilder.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tac_users',
        filter: mission == null
            ? null
            : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
        callback: (payload) {
          if (!mounted) return;
          if (payload.eventType == PostgresChangeEvent.delete) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) setState(() => _users.remove(id));
          } else {
            final u = TacUser.fromMap(payload.newRecord);
            final existing = _users[u.id];
            if (existing == null || u.updatedAt.isAfter(existing.updatedAt)) {
              setState(() => _users[u.id] = u);
            }
          }
        });
    channelBuilder = channelBuilder.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tac_zones',
        filter: mission == null
            ? null
            : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
        callback: (payload) {
          if (!mounted) return;
          if (payload.eventType == PostgresChangeEvent.delete) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) setState(() => _zones.remove(id));
          } else {
            final z = TacZone.fromMap(payload.newRecord);
            setState(() => _zones[z.id] = z);
          }
        });
    channelBuilder = channelBuilder.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tac_markers',
        filter: mission == null
            ? null
            : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
        callback: (payload) {
          if (!mounted) return;
          if (payload.eventType == PostgresChangeEvent.delete) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) setState(() => _markers.remove(id));
          } else {
            final m = TacMarker.fromMap(payload.newRecord);
            setState(() => _markers[m.id] = m);
          }
        });
    channelBuilder = channelBuilder.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tac_sos',
        filter: mission == null
            ? null
            : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'mission_code', value: mission),
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
        });
    _channel = channelBuilder.subscribe();
  }

  void _fitToMarkers() {
    final points = [
      ..._visibleUsers.map((u) => LatLng(u.lat, u.lng)),
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<_MapMode>(
          segments: const [
            ButtonSegment(value: _MapMode.allUsers, label: Text('All Users'), icon: Icon(Icons.public)),
            ButtonSegment(
                value: _MapMode.thisIncident,
                label: Text('This Incident'),
                icon: Icon(Icons.local_fire_department)),
          ],
          selected: {_mode},
          onSelectionChanged: widget.incident == null ? null : (s) => _setMode(s.first),
        ),
      ),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final visible = _visibleUsers.toList();
    final center = visible.isNotEmpty
        ? LatLng(visible.first.lat, visible.first.lng)
        : const LatLng(39.8283, -98.5795); // continental US fallback

    return Row(
      children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(initialCenter: center, initialZoom: visible.isEmpty ? 4 : 13),
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
                  ...visible.map((u) => Marker(
                        point: LatLng(u.lat, u.lng),
                        width: 120,
                        height: 56,
                        child: _UserMarker(
                          user: u,
                          showMission: _mode == _MapMode.allUsers,
                          resourceType: _resourceTypeByUser[u.id],
                          teamName: _teamNameByUser[u.id],
                          teamColor: _teamColorByUser[u.id],
                          deploymentStatus: _deploymentStatusByUser[u.id],
                        ),
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
                Text('On map (${visible.length})', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...visible.map((u) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle, size: 12, color: Colors.green),
                      title: Text(u.callsign),
                      subtitle: Text(_mode == _MapMode.allUsers
                          ? '${u.missionCode.isEmpty ? 'no mission' : u.missionCode} • ${u.batteryLevel ?? '—'}%'
                          : '${u.status} • ${u.batteryLevel ?? '—'}%'),
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
                        trailing: TextButton(
                          onPressed: () => _resolveSos(s),
                          child: const Text('Resolve'),
                        ),
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
  final bool showMission;
  final String? resourceType;
  final String? teamName;
  final Color? teamColor;
  final String? deploymentStatus;
  const _UserMarker({
    required this.user,
    this.showMission = false,
    this.resourceType,
    this.teamName,
    this.teamColor,
    this.deploymentStatus,
  });

  @override
  Widget build(BuildContext context) {
    final rt = resourceType ?? '';
    final icon = rt.isNotEmpty ? resourceTypeIcon(rt) : Icons.person_pin_circle;
    final color = teamColor ?? Colors.teal;
    return GestureDetector(
      onTap: () => showPersonnelInfoSheet(
        context,
        userId: user.id,
        callsign: user.callsign,
        resourceType: resourceType,
        teamName: teamName,
        teamColor: teamColor,
        deploymentStatus: deploymentStatus,
        assignedBy: 'Command Console',
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
            // Team-color ring so team members read as visually grouped even
            // when their resource_type/icon differs.
            border: teamColor != null ? Border.all(color: teamColor!, width: 2) : null,
          ),
          child: Text(
            showMission && user.missionCode.isNotEmpty ? '${user.callsign} · ${user.missionCode}' : user.callsign,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Icon(icon, color: color, size: 32),
      ]),
    );
  }
}
