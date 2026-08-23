import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../wildfire_overlay.dart';
import '../tac_map.dart'
    show
        TacUser,
        TacZone,
        TacMarker,
        TacMarkerType,
        TacSosEvent,
        resourceTypeIcon,
        parseHexColor,
        showPersonnelInfoSheet,
        kZoneTypes,
        kLocationStaleAfter,
        kLocationRemoveAfter,
        TacBaseLayer,
        insertTacMarker,
        insertTacZone,
        waypointRoutePoints,
        firstMarkerOfType,
        groupMarkersByMission,
        loadHiddenMarkerTypes,
        saveHiddenMarkerTypes,
        loadHiddenZoneTypes,
        saveHiddenZoneTypes,
        formatMarkerTimestamp,
        parseLatLng,
        parseUsng;
import '../incident_service.dart';
import '../routing_service.dart';

// A device publishes every ~10s while sharing location, but background-
// tracked devices can go quiet for a few minutes under OS battery throttling
// without meaning "gone" -- use the shared kLocationRemoveAfter (15 min) as
// the hard cutoff, matching tac_map.dart's own peer-view threshold, rather
// than a tighter one specific to this screen (tac_users has no TTL of its
// own; see joinMissionSilently for the related fix to stop old-mission rows
// from lingering in the first place).
const _kCurrentWindow = kLocationRemoveAfter;

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
  String? _error;
  late _MapMode _mode;
  Timer? _agingTimer;
  Timer? _refreshTimer;

  // Marker/zone placement (new — this screen was view-only before)
  TacMarkerType? _placingType;
  bool _placingZone = false;
  TacBaseLayer _baseLayer = TacBaseLayer.osm;
  IncidentOverlay? _incidentOverlay;
  bool _fireMapAsBase = false;
  Set<TacMarkerType> _hiddenMarkerTypes = {};
  Set<String> _hiddenZoneTypes = {};

  // Dispatch ETA: pick a deployed unit, then a destination marker, to get a
  // road-based distance/ETA between them (the Console has no GPS of its own,
  // so this is the desktop equivalent of mobile's self-navigation feature).
  bool _pickingRoute = false;
  TacUser? _routeOriginUser;
  RouteResult? _navRoute;
  TacMarker? _navTarget;
  bool _routing = false;

  // Multi-stop route planning — tap existing markers in order (origin, any
  // points between, destination) for a total ETA plus a per-segment
  // breakdown. Mutually exclusive with Dispatch ETA above.
  bool _planningRoute = false;
  final List<TacMarker> _routeStops = [];
  MultiRouteResult? _multiRoute;
  bool _isMultiRouting = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.incident == null ? _MapMode.allUsers : _MapMode.thisIncident;
    _bind();
    _loadLayerVisibility();
    // _users doesn't change on its own between publishes, but "is this still
    // current" does as time passes — re-render periodically so a marker
    // actually disappears once its owner stops transmitting, rather than
    // only when the next unrelated update happens to trigger a rebuild.
    _agingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Safety net: the realtime channel is supposed to push every update
    // live, but if its WebSocket silently drops (network blip, idle
    // disconnect) with no error surfaced, tac_users stops updating and
    // everyone quietly ages out past _kCurrentWindow with no visible cause
    // — this periodically re-syncs from a plain REST fetch regardless of
    // realtime's own health, so the map self-heals either way.
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _refreshUsers());
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
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Silent, non-disruptive re-sync of tac_users only — unlike _bind(),
  /// doesn't clear existing state or show a loading spinner, so it's safe
  /// to run on a timer in the background without the map flashing blank.
  Future<void> _refreshUsers() async {
    if (!mounted) return;
    final client = SupabaseService.client;
    if (client == null) return;
    final mission = _missionFilter;
    try {
      final rows = mission == null
          ? await client.from('tac_users').select()
          : await client.from('tac_users').select().eq('mission_code', mission);
      final fresh = <String, TacUser>{};
      for (final r in rows as List) {
        final u = TacUser.fromMap(r as Map<String, dynamic>);
        final existing = fresh[u.id];
        if (existing == null || u.updatedAt.isAfter(existing.updatedAt)) {
          fresh[u.id] = u;
        }
      }
      if (mounted) {
        setState(() {
          _users
            ..clear()
            ..addAll(fresh);
        });
      }
    } catch (_) {
      // Transient — the next timer tick or a live realtime update will
      // catch up; no need to surface this as a hard error like _bind()'s
      // initial load does.
    }
  }

  // A previous version of this file force-recreated the channel whenever
  // its status went to closed/channelError/timedOut, on the theory that a
  // dropped socket would otherwise sit stale forever. In practice the
  // realtime client already auto-rejoins on its own within tens of
  // milliseconds of a drop — the forced recreation was firing 2 seconds
  // after every drop (including ones the library had already healed),
  // which itself produced a new "closed" event and re-armed the same
  // 2-second timer, so it never stopped: confirmed via a debug log showing
  // closed/subscribed pairs repeating exactly every ~2.0s indefinitely.
  // The periodic _refreshUsers() REST poll is a sufficient, non-disruptive
  // safety net for the case where the socket is ever genuinely stuck, so
  // there is no channel-status handling here at all now.

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
    setState(() { _loading = true; _error = null; });

    final client = SupabaseService.client;
    if (client == null) {
      if (mounted) setState(() { _loading = false; _error = 'Not connected to Supabase.'; });
      return;
    }
    final mission = _missionFilter;

    try {
      // Run every fetch in parallel (rather than 6 sequential awaits) so a
      // single slow query doesn't multiply the total wait, and cap the whole
      // batch with a timeout — previously a stalled/failed query here was
      // swallowed by a bare `catch (_) {}` with no timeout at all, leaving
      // every map empty (already cleared above) and _loading set to false:
      // a genuinely blank map with no indication anything went wrong.
      final results = await Future.wait([
        mission == null ? client.from('tac_users').select() : client.from('tac_users').select().eq('mission_code', mission),
        mission == null ? client.from('tac_zones').select() : client.from('tac_zones').select().eq('mission_code', mission),
        mission == null ? client.from('tac_markers').select() : client.from('tac_markers').select().eq('mission_code', mission),
        mission == null ? client.from('tac_sos').select() : client.from('tac_sos').select().eq('mission_code', mission),
        client.from('teams').select('id, name, color_hex'),
        client.from('user_profiles').select('user_id, resource_type, team_id, deployment_status'),
      ]).timeout(const Duration(seconds: 15));

      for (final r in results[0] as List) {
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
      for (final r in results[1] as List) {
        final z = TacZone.fromMap(r as Map<String, dynamic>);
        _zones[z.id] = z;
      }
      for (final r in results[2] as List) {
        final m = TacMarker.fromMap(r as Map<String, dynamic>);
        _markers[m.id] = m;
      }
      for (final r in results[3] as List) {
        final s = TacSosEvent.fromMap(r as Map<String, dynamic>);
        if (!s.resolved) _sos[s.id] = s;
      }
      // Personnel role/team — separate tables from tac_users (location), so
      // resolved into lookup maps here rather than joined server-side.
      final colorByTeam = <String, Color>{};
      final nameByTeam = <String, String>{};
      for (final r in results[4] as List) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        final color = parseHexColor(m['color_hex'] as String?);
        if (color != null) colorByTeam[id] = color;
        nameByTeam[id] = m['name'] as String? ?? '';
      }
      for (final r in results[5] as List) {
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
    } on TimeoutException {
      if (mounted) {
        setState(() { _loading = false; _error = 'Loading timed out — check your connection and try again.'; });
      }
      return;
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load map data: $e'; });
      return;
    }

    if (mounted) setState(() => _loading = false);
    _fitToMarkers();
    _subscribeChannel();
  }

  void _subscribeChannel() {
    final client = SupabaseService.client;
    if (client == null) return;
    final mission = _missionFilter;
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

  // ── Layer visibility (hide by type — local-only, persisted, non-destructive) ─

  Future<void> _loadLayerVisibility() async {
    final markerTypes = await loadHiddenMarkerTypes();
    final zoneTypes = await loadHiddenZoneTypes();
    if (mounted) setState(() { _hiddenMarkerTypes = markerTypes; _hiddenZoneTypes = zoneTypes; });
  }

  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Markers', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...TacMarkerType.values.map((t) => CheckboxListTile(
                  value: !_hiddenMarkerTypes.contains(t),
                  secondary: Icon(t.icon, color: t.color),
                  title: Text(t.label),
                  onChanged: (checked) {
                    ss(() => setState(() {
                          if (checked == true) {
                            _hiddenMarkerTypes.remove(t);
                          } else {
                            _hiddenMarkerTypes.add(t);
                          }
                        }));
                    saveHiddenMarkerTypes(_hiddenMarkerTypes);
                  },
                )),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Zones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...kZoneTypes.map((t) => CheckboxListTile(
                  value: !_hiddenZoneTypes.contains(t),
                  title: Text(t),
                  onChanged: (checked) {
                    ss(() => setState(() {
                          if (checked == true) {
                            _hiddenZoneTypes.remove(t);
                          } else {
                            _hiddenZoneTypes.add(t);
                          }
                        }));
                    saveHiddenZoneTypes(_hiddenZoneTypes);
                  },
                )),
          ],
        ),
      )),
    );
  }

  // ── Placement (new surface area — this screen had no way to create
  // markers/zones before; desktop-appropriate menu + map-click flow) ─────────

  void _startPlacingMarker(TacMarkerType type) {
    if (widget.incident == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select an incident to place markers')));
      return;
    }
    setState(() {
      _placingType = _placingType == type ? null : type;
      _placingZone = false;
    });
  }

  void _startPlacingZone() {
    if (widget.incident == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select an incident to place zones')));
      return;
    }
    setState(() { _placingZone = !_placingZone; _placingType = null; });
  }

  Future<void> _placeMarkerDesktop(LatLng pos, TacMarkerType type) async {
    setState(() => _placingType = null);
    await _placeMarkerAtPointDesktop(pos, type);
  }

  /// Shared by map-click placement and the "Add by Coordinates" dialog.
  Future<void> _placeMarkerAtPointDesktop(LatLng pos, TacMarkerType type, {String? label}) async {
    final missionCode = widget.incident!.missionCode;
    final effectiveLabel = label ?? (type == TacMarkerType.obstacle ? formatMarkerTimestamp(DateTime.now()) : '');
    try {
      final saved = await insertTacMarker(SupabaseService.client!,
          missionCode: missionCode, type: type, label: effectiveLabel,
          lat: pos.latitude, lng: pos.longitude, placedBy: 'Command Console');
      // Add directly rather than waiting on realtime — that needs the table
      // in the realtime publication (a one-time migration step) and even
      // then there's no reason to round-trip through it just to see your
      // own just-placed marker.
      if (mounted) setState(() => _markers[saved.id] = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place marker: $e')));
      }
    }
  }

  Future<void> _placeWaypointDesktop(LatLng pos) async {
    setState(() => _placingType = null);
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
    final wpLabel = label?.isNotEmpty == true ? label! : 'WP';
    await _placeMarkerAtPointDesktop(pos, TacMarkerType.waypoint, label: wpLabel);
  }

  Future<void> _loadWildfireOverlay(String url, String name, {bool asBase = false}) async {
    final snack = ScaffoldMessenger.of(context);
    snack.showSnackBar(SnackBar(
        content: Text('Downloading $name…'),
        duration: const Duration(seconds: 30)));
    try {
      final overlay = await loadWildfireOverlay(url, name);
      if (mounted) {
        snack.hideCurrentSnackBar();
        setState(() {
          _incidentOverlay = overlay;
          if (asBase) _fireMapAsBase = true;
        });
        _mapCtrl.fitCamera(
            CameraFit.bounds(bounds: overlay.bounds, padding: const EdgeInsets.all(16)));
        snack.showSnackBar(SnackBar(
            content: Text('Loaded: $name'),
            duration: const Duration(seconds: 3)));
      }
    } catch (e) {
      if (mounted) {
        snack.hideCurrentSnackBar();
        snack.showSnackBar(SnackBar(
            content: Text('Failed to load map: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4)));
      }
    }
  }

  void _showWildfireBrowser() {
    showWildfireBrowserDialog(context, onLoad: (url, name, {bool asBase = false}) {
      Navigator.pop(context);
      _loadWildfireOverlay(url, name, asBase: asBase);
    });
  }

  void _showBaseLayerPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Base Map Layer', style: TextStyle(fontWeight: FontWeight.bold))),
          ...TacBaseLayer.values.map((layer) => ListTile(
                title: Text(layer.label),
                leading: Icon(_baseLayer == layer
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                onTap: () {
                  setState(() => _baseLayer = layer);
                  Navigator.pop(context);
                },
              )),
        ]),
      ),
    );
  }

  /// Right-click anywhere on the map to place a marker at that exact spot,
  /// without first selecting a type from the toolbar -- the desktop
  /// equivalent of the mobile field app's long-press-to-place gesture.
  Future<void> _onMapRightClick(Offset localPosition) async {
    if (widget.incident == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select an incident to place markers')));
      return;
    }
    final point = _mapCtrl.camera.pointToLatLng(Point(localPosition.dx, localPosition.dy));
    final type = await showDialog<TacMarkerType>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add Marker Here'),
        children: TacMarkerType.values
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, t),
                  child: Row(children: [
                    Icon(t.icon, color: t.color, size: 18),
                    const SizedBox(width: 10),
                    Text(t.label),
                  ]),
                ))
            .toList(),
      ),
    );
    if (type == null || !mounted) return;
    if (type == TacMarkerType.waypoint) {
      await _placeWaypointDesktop(point);
    } else {
      await _placeMarkerAtPointDesktop(point, type);
    }
  }

  /// Place a marker without needing to click the map — enter decimal
  /// lat/lng or a USNG/MGRS grid reference directly.
  Future<void> _showAddByCoordinatesDialog() async {
    if (widget.incident == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select an incident to place markers')));
      return;
    }
    TacMarkerType type = TacMarkerType.waypoint;
    bool useUsng = false;
    String coordText = '';
    String labelText = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: const Text('Add Marker by Coordinates'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<TacMarkerType>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Marker type', border: OutlineInputBorder()),
              items: TacMarkerType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.icon, color: t.color, size: 16),
                          const SizedBox(width: 6),
                          Text(t.label),
                        ]),
                      ))
                  .toList(),
              onChanged: (v) => ss(() => type = v ?? type),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Lat/Lng')),
                ButtonSegment(value: true, label: Text('USNG/MGRS')),
              ],
              selected: {useUsng},
              onSelectionChanged: (s) => ss(() => useUsng = s.first),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: useUsng ? 'USNG/MGRS grid reference' : 'Latitude, Longitude',
                hintText: useUsng ? '18SUJ2338308450' : '34.0522, -118.2437',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => coordText = v,
            ),
            if (type == TacMarkerType.waypoint) ...[
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(labelText: 'Waypoint name (optional)', border: OutlineInputBorder()),
                onChanged: (v) => labelText = v,
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Place')),
        ],
      )),
    );
    if (result != true) return;
    final point = useUsng ? parseUsng(coordText) : parseLatLng(coordText);
    if (point == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not parse ${useUsng ? 'USNG/MGRS' : 'lat/lng'} coordinates'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }
    final label = type == TacMarkerType.waypoint
        ? (labelText.trim().isNotEmpty ? labelText.trim() : 'WP')
        : null;
    await _placeMarkerAtPointDesktop(point, type, label: label);
  }

  Future<void> _createZoneDesktop(LatLng pos) async {
    setState(() => _placingZone = false);
    String? name;
    String zoneType = 'LZ';
    double radiusM = 100;
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
            initialValue: zoneType,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
            items: kZoneTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
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
      final saved = await insertTacZone(SupabaseService.client!,
          missionCode: widget.incident!.missionCode, name: name!, zoneType: zoneType,
          lat: pos.latitude, lng: pos.longitude, radiusM: radiusM, createdBy: 'Command Console');
      if (mounted) setState(() => _zones[saved.id] = saved);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Zone create failed: $e')));
    }
  }

  void _confirmDeleteMarkerDesktop(TacMarker m) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Marker?'),
        content: Text('${m.type.label} placed by ${m.placedBy}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await SupabaseService.client?.from('tac_markers').delete().eq('id', m.id);
                if (mounted) setState(() => _markers.remove(m.id));
              } catch (_) {}
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Bulk-clear every marker of a type — for clearing out outdated
  /// markers in one action instead of long-pressing each one individually.
  Future<void> _clearMarkersByTypeDesktop(TacMarkerType type) async {
    final toDelete = _markers.values.where((m) => m.type == type).map((m) => m.id).toList();
    if (toDelete.isEmpty) return;
    final client = SupabaseService.client;
    if (client == null) return;
    for (final id in toDelete) {
      try { await client.from('tac_markers').delete().eq('id', id); } catch (_) {}
    }
    if (mounted) setState(() { for (final id in toDelete) { _markers.remove(id); } });
  }

  void _confirmDeleteZoneDesktop(TacZone z) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Zone?'),
        content: Text('Remove "${z.name}" (${z.zoneType})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try { await SupabaseService.client?.from('tac_zones').delete().eq('id', z.id); } catch (_) {}
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ── Dispatch ETA (Console's equivalent of mobile's self-navigation — no
  // GPS of its own, so route between a deployed unit and a destination) ──────

  void _toggleDispatchPicker() {
    setState(() {
      _pickingRoute = !_pickingRoute;
      _routeOriginUser = null;
      if (!_pickingRoute) { _navRoute = null; _navTarget = null; }
      if (_pickingRoute) { _planningRoute = false; _routeStops.clear(); _multiRoute = null; }
    });
  }

  void _onUserTapped(TacUser u) {
    if (_pickingRoute && _routeOriginUser == null) {
      setState(() => _routeOriginUser = u);
      return;
    }
  }

  Future<void> _onMarkerTapped(TacMarker m) async {
    if (_pickingRoute && _routeOriginUser != null) {
      await _computeDispatchRoute(_routeOriginUser!, m);
      return;
    }
    if (_planningRoute) {
      _toggleRouteStop(m);
    }
  }

  // ── Multi-stop route planning ────────────────────────────────────────────

  void _toggleRoutePlanning() {
    setState(() {
      _planningRoute = !_planningRoute;
      if (!_planningRoute) _routeStops.clear();
      _multiRoute = null;
      if (_planningRoute) { _pickingRoute = false; _routeOriginUser = null; _navRoute = null; _navTarget = null; }
    });
  }

  void _toggleRouteStop(TacMarker m) {
    setState(() {
      final existing = _routeStops.indexWhere((s) => s.id == m.id);
      if (existing != -1) {
        _routeStops.removeAt(existing);
      } else {
        _routeStops.add(m);
      }
    });
  }

  String _stopLabel(int index) {
    if (index < 0 || index >= _routeStops.length) return '?';
    final m = _routeStops[index];
    return m.label.isNotEmpty ? m.label : m.type.label;
  }

  Future<void> _calculateMultiRoute() async {
    if (_routeStops.length < 2) return;
    setState(() => _isMultiRouting = true);
    try {
      final result = await OsrmRoutingService.routeMultiple(
          _routeStops.map((m) => LatLng(m.lat, m.lng)).toList());
      if (mounted) {
        setState(() {
          _multiRoute = result;
          _planningRoute = false;
          _isMultiRouting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isMultiRouting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is RoutingException ? e.message : 'Routing failed'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  Future<void> _computeDispatchRoute(TacUser origin, TacMarker dest) async {
    setState(() => _routing = true);
    try {
      final result = await OsrmRoutingService.route(LatLng(origin.lat, origin.lng), LatLng(dest.lat, dest.lng));
      if (mounted) {
        setState(() {
          _navRoute = result;
          _navTarget = dest;
          _pickingRoute = false;
          _routeOriginUser = null;
          _routing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _pickingRoute = false; _routeOriginUser = null; _routing = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is RoutingException ? e.message : 'Routing failed'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          SegmentedButton<_MapMode>(
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
          const SizedBox(width: 12),
          PopupMenuButton<TacMarkerType>(
            tooltip: 'Place a marker',
            onSelected: _startPlacingMarker,
            itemBuilder: (_) => TacMarkerType.values
                .map((t) => PopupMenuItem(
                      value: t,
                      child: Row(children: [
                        Icon(t.icon, color: t.color, size: 18),
                        const SizedBox(width: 8),
                        Text(t.label),
                      ]),
                    ))
                .toList(),
            child: InputChip(
              label: const Text('Place Marker'),
              avatar: const Icon(Icons.add_location_alt_outlined, size: 18),
              selected: _placingType != null,
              onPressed: null,
            ),
          ),
          const SizedBox(width: 8),
          InputChip(
            label: const Text('Add Zone'),
            avatar: const Icon(Icons.circle_outlined, size: 18),
            selected: _placingZone,
            onPressed: _startPlacingZone,
          ),
          const SizedBox(width: 8),
          InputChip(
            label: const Text('Dispatch ETA'),
            avatar: const Icon(Icons.alt_route, size: 18),
            selected: _pickingRoute,
            onPressed: _toggleDispatchPicker,
          ),
          const SizedBox(width: 8),
          InputChip(
            label: const Text('Plan Route'),
            avatar: const Icon(Icons.route, size: 18),
            selected: _planningRoute || _multiRoute != null,
            onPressed: _toggleRoutePlanning,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Layers',
            onPressed: _showLayersSheet,
            icon: Icon(Icons.checklist,
                color: (_hiddenMarkerTypes.isNotEmpty || _hiddenZoneTypes.isNotEmpty)
                    ? Theme.of(context).colorScheme.primary : null),
          ),
          PopupMenuButton<TacMarkerType>(
            tooltip: 'Clear outdated markers',
            onSelected: _clearMarkersByTypeDesktop,
            itemBuilder: (_) => TacMarkerType.values
                .map((t) => PopupMenuItem(value: t, child: Text('Clear all ${t.label} markers')))
                .toList(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.layers_clear),
            ),
          ),
          IconButton(
            tooltip: 'Add Marker by Coordinates',
            onPressed: _showAddByCoordinatesDialog,
            icon: const Icon(Icons.pin_drop_outlined),
          ),
          if (_placingType != null || _placingZone || _pickingRoute || _planningRoute) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _placingType != null
                    ? 'Click the map to place ${_placingType!.label}'
                    : _placingZone
                        ? 'Click the map to place the zone centre'
                        : _planningRoute
                            ? 'Click markers in order: origin, then any stops, then destination'
                            : _routeOriginUser == null
                                ? 'Click a unit, then a destination marker'
                                : 'Click a destination marker for ${_routeOriginUser!.callsign}',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ]),
      ),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _bind, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      );
    }

    final visible = _visibleUsers.toList();
    final visibleZones = _zones.values.where((z) => !_hiddenZoneTypes.contains(z.zoneType));
    final visibleMarkers = _markers.values.where((m) => !_hiddenMarkerTypes.contains(m.type));

    // Route lines, grouped by mission so "All Users" mode never connects
    // waypoints/extraction points that belong to different missions.
    final polylines = <Polyline>[];
    for (final group in groupMarkersByMission(visibleMarkers).values) {
      final start = firstMarkerOfType(group, TacMarkerType.extractionStart);
      final end = firstMarkerOfType(group, TacMarkerType.extractionEnd);
      if (start != null && end != null) {
        polylines.add(Polyline(points: [start, end], color: Colors.orange, strokeWidth: 3));
      }
      final wpPts = waypointRoutePoints(group);
      if (wpPts.length >= 2) {
        polylines.add(Polyline(points: wpPts, color: TacMarkerType.waypoint.color, strokeWidth: 3));
      }
    }
    if (_navRoute != null) {
      polylines.add(Polyline(points: _navRoute!.points, color: Colors.cyanAccent, strokeWidth: 4));
    }
    if (_multiRoute != null) {
      polylines.add(Polyline(points: _multiRoute!.points, color: Colors.amberAccent, strokeWidth: 4));
    }

    return Row(
      children: [
        Expanded(
          child: Stack(children: [
            GestureDetector(
              onSecondaryTapUp: (details) => _onMapRightClick(details.localPosition),
              child: FlutterMap(
              mapController: _mapCtrl,
              // Fixed initial camera only — real positioning is done via _mapCtrl
              // (see _fitToMarkers) so periodic data refreshes don't reset pan/zoom.
              options: MapOptions(
                initialCenter: const LatLng(39.8283, -98.5795),
                initialZoom: 4,
                onTap: (_, point) {
                  if (_placingZone) { _createZoneDesktop(point); return; }
                  if (_placingType == TacMarkerType.waypoint) { _placeWaypointDesktop(point); return; }
                  if (_placingType != null) { _placeMarkerDesktop(point, _placingType!); return; }
                },
              ),
              children: [
                Opacity(
                  opacity: (_fireMapAsBase && _incidentOverlay?.imageBytes != null) ? 0.0 : 1.0,
                  child: TileLayer(
                    urlTemplate: _baseLayer.urlTemplate,
                    subdomains: _baseLayer == TacBaseLayer.osm ? const ['a', 'b', 'c'] : const [],
                    userAgentPackageName: 'com.peninsulathreat.resqruck',
                  ),
                ),
                if (_incidentOverlay?.imageBytes != null)
                  OverlayImageLayer(overlayImages: [
                    // RotatedOverlayImage (not OverlayImage) so filterQuality
                    // can be set -- see the matching mobile comment in
                    // tac_map.dart for why plain OverlayImage looks
                    // blocky/blurry once zoomed in.
                    RotatedOverlayImage(
                      topLeftCorner: _incidentOverlay!.bounds.northWest,
                      bottomLeftCorner: _incidentOverlay!.bounds.southWest,
                      bottomRightCorner: _incidentOverlay!.bounds.southEast,
                      imageProvider: MemoryImage(_incidentOverlay!.imageBytes!),
                      opacity: _fireMapAsBase ? 1.0 : 0.7,
                      filterQuality: FilterQuality.high,
                    ),
                  ]),
                if (_incidentOverlay != null && _incidentOverlay!.polygons.isNotEmpty)
                  PolygonLayer(polygons: _incidentOverlay!.polygons
                      .map((pts) => Polygon(
                            points: pts,
                            color: Colors.red.withValues(alpha: 0.20),
                            borderColor: Colors.red,
                            borderStrokeWidth: 2,
                          ))
                      .toList()),
                PolylineLayer(polylines: polylines),
                CircleLayer(
                  circles: visibleZones
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
                  ...visibleZones.map((z) => Marker(
                        point: LatLng(z.lat, z.lng),
                        width: 90,
                        height: 24,
                        child: GestureDetector(
                          onLongPress: () => _confirmDeleteZoneDesktop(z),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: z.color.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(z.name,
                                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      )),
                  ...visibleMarkers.map((m) {
                    final stopIndex = _routeStops.indexWhere((s) => s.id == m.id);
                    return Marker(
                      point: LatLng(m.lat, m.lng),
                      width: m.type.showsLabelPill ? 60 : 36,
                      height: m.type.showsLabelPill ? 44 : 36,
                      child: GestureDetector(
                        onTap: () => _onMarkerTapped(m),
                        onLongPress: () => _confirmDeleteMarkerDesktop(m),
                        child: Stack(clipBehavior: Clip.none, children: [
                          m.type.showsLabelPill
                              ? Column(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: m.type.color, borderRadius: BorderRadius.circular(4)),
                                    child: Text(m.label.isNotEmpty ? m.label : m.type.label,
                                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                  ),
                                  Icon(m.type.icon, color: m.type.color, size: 22),
                                ])
                              : Icon(m.type.icon, color: m.type.color, size: 28),
                          if (stopIndex != -1)
                            Positioned(
                              right: -2, top: -2,
                              child: CircleAvatar(
                                radius: 8, backgroundColor: Colors.amberAccent,
                                child: Text('${stopIndex + 1}',
                                    style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ]),
                      ),
                    );
                  }),
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
                          onTapOverride: _pickingRoute ? () => _onUserTapped(u) : null,
                        ),
                      )),
                ]),
              ],
            ),
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
            Positioned(
              right: 12,
              top: 60,
              child: FloatingActionButton.small(
                heroTag: 'base_layer',
                onPressed: _showBaseLayerPicker,
                tooltip: 'Base map layer',
                child: const Icon(Icons.layers),
              ),
            ),
            Positioned(
              right: 12,
              top: 108,
              child: FloatingActionButton.small(
                heroTag: 'wildfire_overlay',
                onPressed: _showWildfireBrowser,
                tooltip: 'Wildfire incident maps',
                backgroundColor: _incidentOverlay != null ? Colors.deepOrange : null,
                child: Icon(Icons.local_fire_department,
                    color: _incidentOverlay != null ? Colors.white : null),
              ),
            ),
            if (_incidentOverlay != null)
              Positioned(
                left: 12,
                top: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 18),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(_incidentOverlay!.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: Icon(_fireMapAsBase ? Icons.layers : Icons.layers_outlined, size: 18),
                        tooltip: _fireMapAsBase ? 'Show as overlay' : 'Use as basemap',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _fireMapAsBase = !_fireMapAsBase),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() { _incidentOverlay = null; _fireMapAsBase = false; }),
                      ),
                    ]),
                  ),
                ),
              ),
            if (_routing)
              const Positioned(
                left: 12, bottom: 12,
                child: Card(child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Routing…'),
                  ]),
                )),
              ),
            if (_navRoute != null && _navTarget != null && _routeOriginUser == null)
              Positioned(
                left: 12,
                bottom: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.alt_route),
                      const SizedBox(width: 8),
                      Text('${_navTarget!.label.isNotEmpty ? _navTarget!.label : _navTarget!.type.label} · '
                          '${formatDistance(_navRoute!.distanceMeters)} · ${formatDuration(_navRoute!.duration)}'),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() { _navRoute = null; _navTarget = null; }),
                      ),
                    ]),
                  ),
                ),
              ),
            if (_planningRoute)
              Positioned(
                left: 12, right: 12, bottom: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        _routeStops.isEmpty
                            ? 'Click markers in order: origin, then any stops, then destination'
                            : _routeStops.map((m) => m.label.isNotEmpty ? m.label : m.type.label).join(' → '),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        if (_isMultiRouting)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        TextButton(
                          onPressed: _routeStops.isEmpty ? null : () => setState(() => _routeStops.clear()),
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _routeStops.length >= 2 && !_isMultiRouting ? _calculateMultiRoute : null,
                          child: Text('Calculate (${_routeStops.length})'),
                        ),
                      ]),
                    ]),
                  ),
                ),
              )
            else if (_multiRoute != null)
              Positioned(
                left: 12, right: 12, bottom: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.alt_route),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Total: ${formatDistance(_multiRoute!.totalDistanceMeters)} · ${formatDuration(_multiRoute!.totalDuration)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() { _multiRoute = null; _routeStops.clear(); }),
                        ),
                      ]),
                      const Divider(height: 12),
                      for (var i = 0; i < _multiRoute!.legs.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${_stopLabel(i)} → ${_stopLabel(i + 1)}: '
                            '${formatDistance(_multiRoute!.legs[i].distanceMeters)} · '
                            '${formatDuration(_multiRoute!.legs[i].duration)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ]),
                  ),
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
  // When set (Dispatch ETA's unit-picking step), overrides the default tap
  // behavior (showPersonnelInfoSheet) so this marker can be selected as a
  // route origin instead.
  final VoidCallback? onTapOverride;
  const _UserMarker({
    required this.user,
    this.showMission = false,
    this.resourceType,
    this.teamName,
    this.teamColor,
    this.deploymentStatus,
    this.onTapOverride,
  });

  @override
  Widget build(BuildContext context) {
    final rt = resourceType ?? '';
    final icon = rt.isNotEmpty ? resourceTypeIcon(rt) : Icons.person_pin_circle;
    final ageSinceUpdate = DateTime.now().toUtc().difference(user.updatedAt.toUtc());
    final minutesAgo = ageSinceUpdate.inMinutes;
    final timeLabel = minutesAgo < 1 ? 'now' : '${minutesAgo}m';
    // Fade (not remove) once past kLocationStaleAfter -- an admin should be
    // able to tell "current" from "not necessarily current" without the
    // marker vanishing outright (background tracking can go quiet for a few
    // minutes under OS battery throttling).
    final isStale = ageSinceUpdate >= kLocationStaleAfter;
    final baseColor = teamColor ?? Colors.teal;
    final color = isStale ? baseColor.withValues(alpha: 0.5) : baseColor;
    return GestureDetector(
      onTap: onTapOverride ??
          () => showPersonnelInfoSheet(
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
            border: teamColor != null ? Border.all(color: color, width: 2) : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              showMission && user.missionCode.isNotEmpty ? '${user.callsign} · ${user.missionCode}' : user.callsign,
              style: TextStyle(color: Colors.white.withValues(alpha: isStale ? 0.6 : 1), fontSize: 11),
            ),
            Text(timeLabel,
                style: TextStyle(color: Colors.white.withValues(alpha: isStale ? 0.5 : 0.7), fontSize: 8)),
          ]),
        ),
        Icon(icon, color: color, size: 32),
      ]),
    );
  }
}
