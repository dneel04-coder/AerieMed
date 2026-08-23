import 'dart:async';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;
import 'gps_tools.dart';
import 'asset_service.dart';
import 'incident_service.dart';
import 'lz_assessment.dart';
import 'offline_maps.dart';
import 'sun_weather.dart';
import 'user_profile.dart';
import 'routing_service.dart';
import 'package:mgrs_dart/mgrs_dart.dart';
import 'wildfire_overlay.dart';


enum TacBaseLayer {
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


const _kSupabaseUrl = 'tac_supabase_url';
const _kSupabaseKey = 'tac_supabase_anon_key';
const _kCallsign = 'tac_callsign';
const _kMissionCode = 'tac_mission_code';
const _kIsAdmin = 'tac_is_admin';
const _kUserId = 'tac_user_id';

/// Below this age, a personnel marker shows at full color; past it, faded
/// (but still shown) — background-tracked devices can legitimately go quiet
/// for a few minutes under OS battery throttling without meaning "gone."
const kLocationStaleAfter = Duration(minutes: 5);

/// Past this age, a personnel marker is removed entirely — treated as no
/// longer transmitting rather than merely delayed.
const kLocationRemoveAfter = Duration(minutes: 15);

/// Fires whenever this device joins a mission, however that happened — via
/// the Join Mission sheet below, or a silent accept-flow elsewhere in the
/// app (see joinMissionSilently). The Tac Map screen is kept alive for the
/// whole app session (IndexedStack in MainShell), so without this signal it
/// has no way to know a join happened anywhere but its own bottom sheet.
class TacMissionBus {
  TacMissionBus._();
  static final ValueNotifier<int> listenable = ValueNotifier<int>(0);
  static void notifyChanged() => listenable.value++;
}

/// Writes the SharedPreferences that put this device "on" a mission, without
/// going through the Join Mission UI. Used by that screen's own submit
/// handler below and by the mobile "accept mission assignment" prompt.
Future<void> joinMissionSilently({
  required String callsign,
  required String missionCode,
  bool isAdmin = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(_kUserId) ?? '';
  await prefs.setString(_kCallsign, callsign);
  await prefs.setString(_kMissionCode, missionCode);
  await prefs.setBool(_kIsAdmin, isAdmin);
  // tac_users' primary key is (id, mission_code), so switching missions
  // without restarting the app (e.g. accepting a new assignment) would
  // otherwise leave the old mission's row behind forever — only an app
  // cold-start cleans those up today. Drop anything under a different
  // mission_code for this device right when we join the new one.
  if (userId.isNotEmpty) {
    try {
      await Supabase.instance.client
          .from('tac_users')
          .delete()
          .eq('id', userId)
          .neq('mission_code', missionCode);
    } catch (_) {}
  }
  TacMissionBus.notifyChanged();
}

enum TacMarkerType {
  patient,
  extractionStart,
  extractionEnd,
  waypoint,
  obstacle,
  rallyPoint;

  String get label => switch (this) {
        patient        => 'Patient',
        extractionStart => 'Extract Start',
        extractionEnd  => 'Extract End',
        waypoint       => 'Waypoint',
        obstacle       => 'Obstacle',
        rallyPoint     => 'Rally Point',
      };

  Color get color => switch (this) {
        patient        => Colors.red,
        extractionStart => Colors.orange,
        extractionEnd  => Colors.green,
        waypoint       => const Color(0xFF9C27B0),
        obstacle       => Colors.amber.shade700,
        rallyPoint     => Colors.blueAccent,
      };

  IconData get icon => switch (this) {
        patient        => Icons.personal_injury,
        extractionStart => Icons.flag,
        extractionEnd  => Icons.local_hospital,
        waypoint       => Icons.place,
        obstacle       => Icons.warning_amber_rounded,
        rallyPoint     => Icons.groups,
      };

  // Types that render a persistent label pill above the pin (see
  // _buildMapMarkers) rather than a bare icon — waypoints show their name,
  // obstacles show when they were reported.
  bool get showsLabelPill => this == waypoint || this == obstacle;
}

// mm/dd HH:mm in local time — used to auto-label obstacle markers with when
// they were placed, visibly on the map (not just in a detail sheet).
String formatMarkerTimestamp(DateTime dt) {
  final l = dt.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(l.month)}/${p2(l.day)} ${p2(l.hour)}:${p2(l.minute)}';
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

/// Individual single-resource categories (user_profiles.resource_type) —
/// wildland fire ICS conventions, including non-firefighting medical
/// single resources. Free text in the DB; this is just what pickers offer.
const List<String> kResourceTypes = [
  'EMT',
  'EMT-Paramedic',
  'Rope Rescue Technician',
  'Driver/Operator',
  'Team Leader',
  'Single Resource Paramedic',
  'Single Resource EMT',
];

/// Maps a personnel resource_type (user_profiles.resource_type — wildland
/// fire single-resource categories) to a map marker icon. Placeholder using
/// Material icons pending a supplied custom icon set: swapping in real
/// assets later only needs to change this one function, not any of the
/// call sites that render personnel markers on either map screen.
IconData resourceTypeIcon(String resourceType) => switch (resourceType) {
      'EMT' => Icons.medical_services,
      'EMT-Paramedic' => Icons.local_hospital,
      'Rope Rescue Technician' => Icons.terrain,
      'Driver/Operator' => Icons.local_shipping,
      'Team Leader' => Icons.shield,
      'Single Resource Paramedic' => Icons.medical_information,
      'Single Resource EMT' => Icons.health_and_safety,
      _ => Icons.person_pin_circle,
    };

/// Parses a '#RRGGBB' or '#AARRGGBB' hex string (as stored in
/// teams.color_hex) into a Color. Returns null for anything absent or
/// unparseable so callers fall back to their own default instead of
/// silently showing a wrong color.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

// ── Personnel info sheet — shared by the mobile map and Command Console ───────

/// Color for a user_profiles.deployment_status value — Standby/In
/// Transit/On Mission/Off Duty — used on the personnel info sheet.
Color deploymentStatusColor(String status) => switch (status) {
      'On Mission' => Colors.blue,
      'In Transit' => Colors.orange,
      'Off Duty' => Colors.grey,
      _ => Colors.green, // Standby
    };

/// Shown on long-press (or tap) of a personnel marker: entity info, team,
/// and currently assigned assets, with an action to assign another asset.
Future<void> showPersonnelInfoSheet(
  BuildContext context, {
  required String userId,
  required String callsign,
  String? resourceType,
  String? teamName,
  Color? teamColor,
  String? deploymentStatus,
  String assignedBy = '',
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PersonnelInfoSheet(
      userId: userId,
      callsign: callsign,
      resourceType: resourceType,
      teamName: teamName,
      teamColor: teamColor,
      deploymentStatus: deploymentStatus,
      assignedBy: assignedBy,
    ),
  );
}

class _PersonnelInfoSheet extends StatefulWidget {
  final String userId;
  final String callsign;
  final String? resourceType;
  final String? teamName;
  final Color? teamColor;
  final String? deploymentStatus;
  final String assignedBy;

  const _PersonnelInfoSheet({
    required this.userId,
    required this.callsign,
    this.resourceType,
    this.teamName,
    this.teamColor,
    this.deploymentStatus,
    this.assignedBy = '',
  });

  @override
  State<_PersonnelInfoSheet> createState() => _PersonnelInfoSheetState();
}

class _PersonnelInfoSheetState extends State<_PersonnelInfoSheet> {
  bool _loading = true;
  List<({AssetAssignment assignment, Asset? asset})> _assigned = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final assignments = await AssetService.instance.getAssignmentsFor(AssignableType.user, widget.userId);
    final active = assignments.where((a) => a.isActive).toList();
    final assets = await AssetService.instance.fetchAssets();
    final assetById = {for (final a in assets) a.id: a};
    if (mounted) {
      setState(() {
        _assigned = active.map((a) => (assignment: a, asset: assetById[a.assetId])).toList();
        _loading = false;
      });
    }
  }

  Future<void> _openPicker() async {
    final asset = await showModalBottomSheet<Asset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AssetPickerSheet(),
    );
    if (asset == null || !mounted) return;
    try {
      await AssetService.instance.assignAssetToUser(asset.id, widget.userId, assignedBy: widget.assignedBy);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign asset: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResourceType = widget.resourceType != null && widget.resourceType!.isNotEmpty;
    final hasTeam = widget.teamName != null && widget.teamName!.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: (widget.teamColor ?? Colors.teal).withValues(alpha: 0.2),
              child: Icon(
                hasResourceType ? resourceTypeIcon(widget.resourceType!) : Icons.person_pin_circle,
                color: widget.teamColor ?? Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(widget.callsign, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (widget.deploymentStatus != null && widget.deploymentStatus!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: deploymentStatusColor(widget.deploymentStatus!).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(widget.deploymentStatus!,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: deploymentStatusColor(widget.deploymentStatus!))),
                    ),
                  ],
                ]),
                if (hasResourceType)
                  Text(widget.resourceType!, style: TextStyle(color: Colors.grey[600])),
                if (hasTeam)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(color: widget.teamColor ?? Colors.grey, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(widget.teamName!, style: TextStyle(color: Colors.grey[600])),
                    ]),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Assigned Assets', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()))
          else if (_assigned.isEmpty)
            Text('No assets currently assigned.', style: TextStyle(color: Colors.grey[600]))
          else
            ..._assigned.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(r.asset?.identifier ?? '(deleted asset)'),
                  subtitle: Text(r.asset?.type ?? ''),
                )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openPicker,
              icon: const Icon(Icons.add),
              label: const Text('Assign Asset'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AssetPickerSheet extends StatefulWidget {
  const _AssetPickerSheet();

  @override
  State<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<_AssetPickerSheet> {
  bool _loading = true;
  List<Asset> _available = [];
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final assets = await AssetService.instance.fetchUnassignedAssets();
    if (mounted) setState(() { _available = assets; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final types = _available.map((a) => a.type).toSet().toList()..sort();
    final filtered = _typeFilter == null ? _available : _available.where((a) => a.type == _typeFilter).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Assign Asset', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (types.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All types')),
              ...types.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
            ],
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text('No unassigned assets${_typeFilter != null ? ' of this type' : ''}.',
                          style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final a = filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(a.identifier),
                          subtitle: Text(a.type),
                          onTap: () => Navigator.pop(context, a),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ── Zone types ────────────────────────────────────────────────────────────────
const kZoneTypes = ['Perimeter', 'LZ', 'Base Camp', 'Staging', 'Custom'];

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

class _TacInvite {
  final String id;
  final String fromCallsign;
  final String toCallsign;
  final String missionCode;
  final DateTime createdAt;
  const _TacInvite({
    required this.id, required this.fromCallsign, required this.toCallsign,
    required this.missionCode, required this.createdAt,
  });
  factory _TacInvite.fromMap(Map<String, dynamic> m) => _TacInvite(
    id: m['id'] as String,
    fromCallsign: m['from_callsign'] as String,
    toCallsign: m['to_callsign'] as String,
    missionCode: m['mission_code'] as String,
    createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

class TacMarker {
  final String id;
  final TacMarkerType type;
  final String label;
  final double lat;
  final double lng;
  final String placedBy;
  final DateTime createdAt;
  final String missionCode;

  TacMarker({
    required this.id,
    required this.type,
    required this.label,
    required this.lat,
    required this.lng,
    required this.placedBy,
    required this.createdAt,
    this.missionCode = '',
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
        missionCode: m['mission_code'] as String? ?? '',
      );
}

// ── Coordinate entry — decimal lat/lng or USNG/MGRS grid reference, shared
// by the mobile map and Command Console for the "Add by Coordinates" dialog.
// USNG and MGRS share the same grid-zone/100km-square/easting-northing
// string format and algorithm (USNG is the US civil adaptation of the
// military MGRS grid); mgrs_dart implements that shared algorithm, which is
// accurate enough for field-marker placement at the precision this app needs.

/// Parses "lat, lng" or "lat lng" decimal degrees. Returns null if the text
/// isn't two valid numbers or is out of range.
LatLng? parseLatLng(String input) {
  final parts = input.trim().split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty).toList();
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return LatLng(lat, lng);
}

/// Parses a USNG/MGRS grid reference (e.g. "18SUJ2338308450" or with spaces
/// "18S UJ 23383 08450"). Returns null if it can't be parsed.
LatLng? parseUsng(String input) {
  final cleaned = input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty) return null;
  try {
    final point = Mgrs.toPoint(cleaned); // [lon, lat]
    return LatLng(point[1], point[0]);
  } catch (_) {
    return null;
  }
}

/// Formats a point as a USNG/MGRS grid reference at 1m precision, for
/// display alongside a marker's plain lat/lng. Null on conversion failure
/// (e.g. polar latitudes outside the grid's supported range).
String? formatUsng(LatLng point) {
  try {
    return Mgrs.forward([point.longitude, point.latitude], 5);
  } catch (_) {
    return null;
  }
}

// ── Map annotation helpers — shared by the mobile map and Command Console ────

/// Ordered route points for a set of waypoint markers, oldest→newest —
/// draws as a single continuous "planned route" line through them.
List<LatLng> waypointRoutePoints(Iterable<TacMarker> markers) {
  final wps = markers.where((m) => m.type == TacMarkerType.waypoint).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return wps.map((m) => LatLng(m.lat, m.lng)).toList();
}

LatLng? firstMarkerOfType(Iterable<TacMarker> markers, TacMarkerType type) {
  for (final m in markers) {
    if (m.type == type) return LatLng(m.lat, m.lng);
  }
  return null;
}

/// Groups markers by mission — needed before drawing route lines wherever
/// markers from multiple missions can be visible at once (Command Console's
/// "All Users" mode), so a route never connects points across missions.
Map<String, List<TacMarker>> groupMarkersByMission(Iterable<TacMarker> markers) {
  final out = <String, List<TacMarker>>{};
  for (final m in markers) {
    out.putIfAbsent(m.missionCode, () => []).add(m);
  }
  return out;
}

// Returns the inserted row (via .select().single()) so callers can update
// their own local state directly rather than waiting on a realtime event to
// deliver it back — realtime requires the table to be in the
// supabase_realtime publication (a one-time migration step) and even when
// that's done, there's no reason the placer's own client should have to
// round-trip through realtime just to see something it just created.
Future<TacMarker> insertTacMarker(
  SupabaseClient client, {
  required String missionCode,
  required TacMarkerType type,
  required String label,
  required double lat,
  required double lng,
  required String placedBy,
}) async {
  final row = await client.from('tac_markers').insert({
    'mission_code': missionCode,
    'type': type.name,
    'label': label,
    'lat': lat,
    'lng': lng,
    'placed_by': placedBy,
  }).select().single();
  return TacMarker.fromMap(row);
}

Future<TacZone> insertTacZone(
  SupabaseClient client, {
  required String missionCode,
  required String name,
  required String zoneType,
  required double lat,
  required double lng,
  required double radiusM,
  required String createdBy,
}) async {
  final row = await client.from('tac_zones').insert({
    'mission_code': missionCode,
    'name': name,
    'zone_type': zoneType,
    'lat': lat,
    'lng': lng,
    'radius_m': radiusM,
    'created_by': createdBy,
  }).select().single();
  return TacZone.fromMap(row);
}

// ── Layer visibility — which marker/zone types are hidden, persisted so the
// choice survives an app restart. Hiding is local-only (not synced), and
// deliberately separate from the destructive "clear" actions elsewhere.
const _kHiddenMarkerTypesKey = 'map_hidden_marker_types';
const _kHiddenZoneTypesKey = 'map_hidden_zone_types';

Future<Set<TacMarkerType>> loadHiddenMarkerTypes() async {
  final prefs = await SharedPreferences.getInstance();
  final names = prefs.getStringList(_kHiddenMarkerTypesKey) ?? const [];
  return TacMarkerType.values.where((t) => names.contains(t.name)).toSet();
}

Future<void> saveHiddenMarkerTypes(Set<TacMarkerType> types) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kHiddenMarkerTypesKey, types.map((t) => t.name).toList());
}

Future<Set<String>> loadHiddenZoneTypes() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_kHiddenZoneTypesKey) ?? const []).toSet();
}

Future<void> saveHiddenZoneTypes(Set<String> types) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kHiddenZoneTypesKey, types.toList());
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

// ── OSM standard tile URL — color, reliable, no API key required
const _kBaseTileUrl =
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const _kBaseTileSubdomains = <String>['a', 'b', 'c'];

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
                urlTemplate: _kBaseTileUrl,
                subdomains: _kBaseTileSubdomains,
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
  battery_level int,
  status text default 'Active',
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
exception when others then null; end \$\$;
do \$\$ begin
  alter table tac_users add column if not exists battery_level int;
exception when others then null; end \$\$;
do \$\$ begin
  alter table tac_users add column if not exists status text default 'Active';
exception when others then null; end \$\$;
create table if not exists tac_sos (
  id uuid default gen_random_uuid() primary key,
  mission_code text not null,
  user_id text not null,
  callsign text not null,
  lat double precision not null,
  lng double precision not null,
  triggered_at timestamptz default now(),
  resolved_at timestamptz,
  resolved_by text
);
alter table tac_sos enable row level security;
do \$\$ begin
  create policy "public_access" on tac_sos
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;
do \$\$ begin
  alter publication supabase_realtime add table tac_sos;
exception when others then null; end \$\$;
alter table tac_sos replica identity full;
create table if not exists tac_invites (
  id uuid default gen_random_uuid() primary key,
  from_callsign text not null,
  to_callsign text not null,
  mission_code text not null,
  created_at timestamptz default now(),
  accepted_at timestamptz
);
alter table tac_invites enable row level security;
do \$\$ begin
  create policy "public_access" on tac_invites
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;
do \$\$ begin
  alter publication supabase_realtime add table tac_invites;
exception when others then null; end \$\$;
alter table tac_invites replica identity full;''';

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
  final _missionCtrl = TextEditingController();
  bool _isAdmin = false;
  bool _joining = false;
  UserProfile? _profile;
  List<TacIncident> _openIncidents = [];
  TacIncident? _selectedIncident;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfile.load();
    final incidents = await IncidentService.instance.fetchIncidents(openOnly: true);
    if (mounted) setState(() { _profile = profile; _openIncidents = incidents; });
  }

  // Callsign is set once at login (see UserProfile) — no need to ask again
  // here. This just gives a quick way back to that screen if it needs fixing
  // without reintroducing a text field in the join sheet itself.
  Future<void> _editProfile() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => LoginScreen(onLoggedIn: () => Navigator.pop(context)),
    ));
    _load();
  }

  Future<void> _join() async {
    final profile = _profile;
    final mission = _missionCtrl.text.trim().toUpperCase();
    if (profile == null || mission.isEmpty) return;

    // If a console mission was picked, the typed code must actually match it —
    // picking a name isn't a shortcut to skip knowing the real code.
    final selected = _selectedIncident;
    if (selected != null && mission != selected.missionCode.toUpperCase()) {
      setState(() => _error = 'That code doesn\'t match "${selected.name.isEmpty ? selected.missionCode : selected.name}".');
      return;
    }

    setState(() { _joining = true; _error = null; });

    await joinMissionSilently(
      callsign: profile.displayCallsign,
      missionCode: mission,
      isAdmin: _isAdmin,
    );

    widget.onJoined();
  }

  @override
  void dispose() {
    _missionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Tac Map — Join Mission')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.radar, size: 64, color: Colors.teal),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.person, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Joining as ${profile.displayCallsign}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Edit callsign',
                    onPressed: _editProfile,
                  ),
                ]),
                const SizedBox(height: 16),
                if (_openIncidents.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Active missions',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _openIncidents.map((incident) {
                      final isSelected = _selectedIncident?.id == incident.id;
                      return ChoiceChip(
                        label: Text(incident.name.isEmpty ? incident.missionCode : incident.name),
                        selected: isSelected,
                        onSelected: (v) => setState(() {
                          _selectedIncident = v ? incident : null;
                          _error = null;
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _missionCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Mission Code',
                    hintText: 'ALPHA-01',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.tag),
                    errorText: _error,
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

  // Personnel resource_type + team color, keyed by user_id — resolved once
  // from user_profiles/teams (see _loadPersonnelMeta) rather than joined
  // per-marker, since tac_users (location) and user_profiles (role/team)
  // are separate tables with no server-side join available here.
  final Map<String, String> _resourceTypeByUser = {};
  final Map<String, Color> _teamColorByUser = {};
  final Map<String, String> _teamNameByUser = {};
  final Map<String, String> _deploymentStatusByUser = {};

  RealtimeChannel? _realtimeChannel;
  Timer? _locationTimer;
  Timer? _refreshTimer;
  Timer? _sosTimer;
  StreamSubscription<Position>? _positionStream;

  bool _mapReady = false;
  LatLng? _myLocation;
  TacMarkerType? _placingType;
  TacBaseLayer _baseLayer = TacBaseLayer.osm;
  IncidentOverlay? _incidentOverlay;
  bool _fireMapAsBase = false; // true = fire map replaces tile layer
  bool _markerTableWarned = false;
  bool _sharingLocation = true;
  final Set<String> _shownInviteIds = {};
  String? _filterMission; // null = all missions visible
  bool _hasMission = false; // true once callsign + missionCode are set

  // Life360-style features
  final Battery _batteryPlugin = Battery();
  int? _myBattery;
  String _myStatus = 'Active';
  final Map<String, List<LatLng>> _breadcrumbs = {};
  int _breadcrumbTick = 0;
  bool _showTrails = false; // opt-in — user taps the route icon to enable
  bool _toolsExpanded = true; // right tool column can be collapsed to a single toggle
  final List<TacZone> _zones = [];
  final List<TacSosEvent> _activeSos = [];
  bool _placingZone = false;
  Set<TacMarkerType> _hiddenMarkerTypes = {};
  Set<String> _hiddenZoneTypes = {};

  // Navigation — road route + ETA from current GPS position to a tapped marker
  RouteResult? _navRoute;
  String? _navTargetLabel;
  bool _isRouting = false;

  // Multi-stop route planning — tap existing markers in order (origin, any
  // points between, destination) to get a total ETA plus a per-segment
  // breakdown, unlike the single-destination "Navigate Here" above.
  bool _planningRoute = false;
  final List<TacMarker> _routeStops = [];
  MultiRouteResult? _multiRoute;
  bool _isMultiRouting = false;

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
    _loadLayerVisibility();
    TacMissionBus.listenable.addListener(_onMissionBusChanged);
  }

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

  // A join can now happen without this screen's own bottom sheet (e.g. the
  // mobile "accept mission assignment" prompt in main.dart) — pick it up
  // here since this screen otherwise stays mounted, unaware, for the
  // lifetime of the app session.
  void _onMissionBusChanged() => _reloadMissionState();

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
    // Broadcast location whenever a callsign is configured (mission_code may be empty)
    if (_callsign.isNotEmpty) _startLocationPublish();
    _subscribeRealtime();
    _loadInitialData();
    _loadPersonnelMeta();
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
        // joinMissionSilently() (called by the sheet's own submit handler)
        // already fired TacMissionBus, which triggers _reloadMissionState —
        // don't call it again here or "mission joined" side effects double-fire.
        Navigator.pop(context);
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
    // Tear down any stale subscriptions/timers from a prior leave, then rebuild.
    _realtimeChannel?.unsubscribe();
    _refreshTimer?.cancel();
    _sosTimer?.cancel();
    _locationTimer?.cancel();

    if (_callsign.isNotEmpty) {
      // Immediately show own marker before the Realtime round-trip completes
      final loc = _myLocation;
      if (loc != null) _applyOwnPosition(loc.latitude, loc.longitude);
      _startLocationPublish();
    }
    // Always re-subscribe and reload so other users are visible regardless of mission state
    _subscribeRealtime();
    _loadInitialData();

    if (_hasMission) {
      // Notify all admins that a user has joined / created a mission.
      try {
        await _supabase.from('admin_alerts').insert({
          'type': 'mission_join',
          'title': 'Mission Joined: $_missionCode',
          'callsign': _callsign,
          'body': '$_callsign joined mission $_missionCode',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}
      _dedupOwnCallsign();
      _purgeStaleRoster();
    }
  }

  /// Removes older tac_users rows sharing this callsign under a different id
  /// (e.g. a reinstall generated a new random id, or someone rejoined). Only
  /// targets entries quiet for a bit so two different people who happen to
  /// share a callsign string don't race-delete each other on near-
  /// simultaneous publishes.
  Future<void> _dedupOwnCallsign() async {
    if (_callsign.isEmpty || _missionCode.isEmpty) return;
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 60)).toIso8601String();
      await _supabase
          .from('tac_users')
          .delete()
          .eq('mission_code', _missionCode)
          .eq('callsign', _callsign)
          .neq('id', _userId)
          .lt('updated_at', cutoff);
    } catch (_) {}
  }

  /// Garbage-collects roster entries nobody has published from in over a
  /// week (force-quit, dead battery, never explicitly left the mission).
  Future<void> _purgeStaleRoster() async {
    if (_missionCode.isEmpty) return;
    try {
      final staleCutoff = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
      await _supabase
          .from('tac_users')
          .delete()
          .eq('mission_code', _missionCode)
          .lt('updated_at', staleCutoff);
    } catch (_) {}
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

    // Show last-known position immediately (usually instant) so the icon
    // appears right away without waiting for a fresh GPS fix.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() {
          _myLocation = LatLng(last.latitude, last.longitude);
          _applyOwnPosition(last.latitude, last.longitude);
        });
        if (_mapReady) _mapCtrl.move(_myLocation!, 14);
      }
    } catch (_) {}

    // Refine with a fresh high-accuracy fix.
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
        _applyOwnPosition(pos.latitude, pos.longitude);
      });
      if (_mapReady) _mapCtrl.move(_myLocation!, 14);
    } catch (_) {}

    // Continuous stream — fires on movement ≥5 m so _myLocation stays current
    // without calling getCurrentPosition on every publish tick (eliminates iOS delay).
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
        )).listen((pos) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      if (_callsign.isNotEmpty) _applyOwnPosition(pos.latitude, pos.longitude);
    });
  }

  // Immediately populate _users with our own entry so the callsign marker
  // appears on the map without waiting for the 10-second publish timer.
  void _applyOwnPosition(double lat, double lng) {
    if (_userId.isEmpty || _callsign.isEmpty) return;
    final existing = _users[_userId];
    final now = DateTime.now();
    if (existing == null || now.isAfter(existing.updatedAt)) {
      _users[_userId] = TacUser(
        id: _userId, callsign: _callsign, missionCode: _missionCode,
        lat: lat, lng: lng, isAdmin: _isAdmin, updatedAt: now,
        batteryLevel: _myBattery, status: _myStatus,
      );
    }
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
    // Immediately re-add own marker without waiting for the publish/Realtime cycle
    final loc = _myLocation;
    if (loc != null) _applyOwnPosition(loc.latitude, loc.longitude);
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
    if (_myLocation == null) return; // position stream hasn't fired yet
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    // Roster housekeeping every 360th publish (~hourly) — covers missions
    // nobody rejoins for a long stretch, since _purgeStaleRoster otherwise
    // only runs right after a fresh join.
    if (_breadcrumbTick % 360 == 0) _purgeStaleRoster();
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
              try {
                // DELETE: only oldRecord['id'] is reliable without REPLICA IDENTITY FULL
                if (payload.eventType == PostgresChangeEvent.delete) {
                  final id = payload.oldRecord['id'] as String?;
                  if (id != null) setState(() => _activeSos.removeWhere((s) => s.id == id));
                  return;
                }
                // INSERT / UPDATE: newRecord always has the full row
                final map = payload.newRecord;
                if (map.isEmpty) return;
                final sos = TacSosEvent.fromMap(map);
                setState(() {
                  _activeSos.removeWhere((s) => s.id == sos.id);
                  if (!sos.resolved) _activeSos.add(sos);
                });
                // Only notify peers on a brand-new SOS, not on resolution
                if (payload.eventType == PostgresChangeEvent.insert &&
                    !sos.resolved &&
                    sos.userId != _userId) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('🚨 SOS from ${sos.callsign}!'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 10),
                  ));
                }
              } catch (_) {}
            })
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'tac_invites',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'to_callsign',
                value: _callsign),
            callback: (payload) {
              if (!mounted || payload.newRecord.isEmpty) return;
              _showInviteDialog(_TacInvite.fromMap(payload.newRecord));
            })
        .subscribe((RealtimeSubscribeStatus status, Object? error) {
      // Re-query on every (re)connect so gaps caused by VPN switching or
      // backgrounding don't leave stale state until the 30-second poll fires.
      if (status == RealtimeSubscribeStatus.subscribed) _loadInitialData();
    });
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadInitialData());
    _sosTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _refreshSos());
  }

  Future<void> _checkPendingInvites() async {
    if (_callsign.isEmpty || !mounted) return;
    try {
      final rows = await _supabase
          .from('tac_invites')
          .select()
          .eq('to_callsign', _callsign)
          .filter('accepted_at', 'is', null) as List;
      for (final r in rows) {
        final invite = _TacInvite.fromMap(r as Map<String, dynamic>);
        // Ignore invites older than 10 minutes or already shown
        if (DateTime.now().toUtc().difference(invite.createdAt).inMinutes > 10) continue;
        if (_shownInviteIds.contains(invite.id)) continue;
        _shownInviteIds.add(invite.id);
        if (mounted) _showInviteDialog(invite);
      }
    } catch (_) {}
  }

  Future<void> _loadPersonnelMeta() async {
    try {
      final teamRows = await _supabase.from('teams').select('id, name, color_hex') as List;
      final colorByTeam = <String, Color>{};
      final nameByTeam = <String, String>{};
      for (final r in teamRows) {
        final m = r as Map<String, dynamic>;
        final id = m['id'] as String;
        final color = parseHexColor(m['color_hex'] as String?);
        if (color != null) colorByTeam[id] = color;
        nameByTeam[id] = m['name'] as String? ?? '';
      }
      final profileRows = await _supabase
          .from('user_profiles')
          .select('user_id, resource_type, team_id, deployment_status') as List;
      if (!mounted) return;
      setState(() {
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
      });
    } catch (_) {
      // teams/resource_type/team_id may not exist yet if the schema
      // migration hasn't been run — degrade to the existing generic look.
    }
  }

  Future<void> _loadInitialData() async {
    _checkPendingInvites();
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
      if (!mounted) return;
      // Network errors are transient — silently retry on the next 30-second
      // cycle rather than showing a confusing socket error to the user.
      if (_isNetworkError(e)) return;
      if (_markerTableWarned) return;
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

  static bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('connection refused') ||
        s.contains('network is unreachable');
  }

  static bool _isMarkerTableMissing(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    return code == '42P01' || code == 'PGRST204' ||
        msg.contains('tac_markers') || msg.contains('does not exist');
  }

  Future<void> _placeMarker(LatLng pos, TacMarkerType type) async {
    setState(() => _placingType = null);
    await _placeMarkerAtPoint(pos, type);
  }

  /// Shared by tap-to-place, the naming dialog (waypoint), and the "Add by
  /// Coordinates" dialog — everything that actually creates a tac_markers
  /// row and updates local state, independent of how the point was chosen.
  Future<void> _placeMarkerAtPoint(LatLng pos, TacMarkerType type, {String? label}) async {
    // Obstacles are auto-labeled with when they were reported, shown right
    // on the map pill (see TacMarkerType.showsLabelPill) rather than buried
    // in a detail sheet.
    final effectiveLabel = label ?? (type == TacMarkerType.obstacle ? formatMarkerTimestamp(DateTime.now()) : '');
    // Show immediately — don't wait for Supabase round-trip
    final tempId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _markers[tempId] = TacMarker(
        id: tempId,
        type: type,
        label: effectiveLabel,
        lat: pos.latitude,
        lng: pos.longitude,
        placedBy: _callsign,
        createdAt: DateTime.now(),
        missionCode: _missionCode,
      );
    });
    try {
      final saved = await insertTacMarker(_supabase,
          missionCode: _missionCode, type: type, label: effectiveLabel,
          lat: pos.latitude, lng: pos.longitude, placedBy: _callsign);
      // Swap the temp marker for the real one directly — don't depend on a
      // realtime event to deliver it back (needs the table in the realtime
      // publication, and even then there's no reason to wait on it just to
      // see your own just-placed marker).
      if (mounted) {
        setState(() {
          _markers.remove(tempId);
          _markers[saved.id] = saved;
        });
      }
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

  static const _kSosRowHeight = 32.0;

  double get _sosBannerHeight => _activeSos.length * _kSosRowHeight;

  // Approximate height of the bottom-docked _TeamPanel (MISSION row + PLACE
  // row, only shown once a mission is joined) plus the coordinate bar that's
  // always shown below it. Used so nothing else on screen — the nav/route
  // banners, the right-side tool column — visually overlaps or gets covered
  // by that bottom panel, which paints on top since it's declared last in
  // the Stack.
  double get _bottomChromeHeight => _hasMission ? 125.0 : 40.0;

  Widget _buildSosRow(TacSosEvent s) {
    final isMine = s.userId == _userId;
    final canResolve = isMine || _isAdmin;
    return SizedBox(
      height: _kSosRowHeight,
      child: InkWell(
        onTap: () => _mapCtrl.move(LatLng(s.lat, s.lng), 14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Icon(Icons.sos, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '🚨 SOS — ${s.callsign}',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 12),
              overflow: TextOverflow.ellipsis)),
            if (canResolve)
              TextButton(
                onPressed: () => _resolveSos(s.id),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(isMine ? 'Cancel SOS' : 'Resolve',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _resolveSos(String sosId) async {
    try {
      await _supabase.from('tac_sos').update({
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'resolved_by': _callsign,
      }).eq('id', sosId);
      setState(() => _activeSos.removeWhere((s) => s.id == sosId));
      // Authoritative re-query after a brief pause to confirm the DB committed
      Future.delayed(const Duration(seconds: 3), _refreshSos);
    } catch (_) {}
  }

  Future<void> _refreshSos() async {
    if (_missionCode.isEmpty || !mounted) return;
    try {
      final rows = await _supabase
          .from('tac_sos')
          .select()
          .eq('mission_code', _missionCode)
          .filter('resolved_at', 'is', null) as List;
      if (!mounted) return;
      setState(() {
        _activeSos
          ..clear()
          ..addAll(rows.map((r) => TacSosEvent.fromMap(r as Map<String, dynamic>)));
      });
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
      final saved = await insertTacZone(_supabase,
          missionCode: _missionCode, name: name!, zoneType: zoneType,
          lat: pos.latitude, lng: pos.longitude, radiusM: radiusM, createdBy: _callsign);
      // Add directly rather than waiting on realtime — same reasoning as
      // marker placement above.
      if (mounted) setState(() => _zones.add(saved));
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
    final wpLabel = label?.isNotEmpty == true ? label! : 'WP';
    setState(() => _placingType = null);
    await _placeMarkerAtPoint(pos, TacMarkerType.waypoint, label: wpLabel);
  }

  /// Place a marker without needing to tap the map — enter decimal lat/lng
  /// or a USNG/MGRS grid reference directly (useful when a coordinate comes
  /// in over radio/text rather than being visible on-screen).
  Future<void> _showAddByCoordinatesDialog() async {
    TacMarkerType type = TacMarkerType.waypoint;
    bool useUsng = false;
    String coordText = '';
    String labelText = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        title: const Text('Add Marker by Coordinates'),
        content: SingleChildScrollView(
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
    await _placeMarkerAtPoint(point, type, label: label);
  }

  /// Press-and-hold anywhere on the map to place a marker at that exact
  /// spot, without first selecting a type from the toolbar/team panel. Only
  /// fires when no other placement mode is already active -- the marker/
  /// zone placement overlays (Positioned.fill, painted on top of FlutterMap)
  /// intercept the gesture first when one of those is open.
  Future<void> _onMapLongPress(LatLng point) async {
    final type = await showModalBottomSheet<TacMarkerType>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: TacMarkerType.values
              .map((t) => ListTile(
                    leading: Icon(t.icon, color: t.color),
                    title: Text(t.label),
                    onTap: () => Navigator.pop(context, t),
                  ))
              .toList(),
        ),
      ),
    );
    if (type == null || !mounted) return;
    if (type == TacMarkerType.waypoint) {
      await _placeWaypoint(point);
    } else {
      await _placeMarkerAtPoint(point, type);
    }
  }

  Future<void> _leaveMission() async {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _sosTimer?.cancel();
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
        // Keep _users intact so other users remain visible after leaving.
        // Remove only own entry since we deleted our row above.
        _users.remove(_userId);
        _markers.clear();
      });
      // Re-subscribe so Realtime updates from other users continue arriving.
      _subscribeRealtime();
      _loadInitialData();
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
    TacMissionBus.listenable.removeListener(_onMissionBusChanged);
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _sosTimer?.cancel();
    _positionStream?.cancel();
    _realtimeChannel?.unsubscribe();
    _takChannel?.unsubscribe();
    super.dispose();
  }

  // ── TAK position markers ──────────────────────────────────────────────────
  List<Marker> _buildTakMarkers() {
    return _takPositions.values.map((p) {
      final age = DateTime.now().difference(p.lastUpdated);
      final stale = age >= kLocationStaleAfter;
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
    final staleThreshold = now.subtract(kLocationRemoveAfter);

    // ── User location pins ────────────────────────────────────────────────
    // Deduplicate by callsign: two devices sharing the same callsign should
    // show only one marker (the most recently updated one).
    final Map<String, TacUser> byCallsign = {};
    for (final user in _users.values) {
      if (user.updatedAt.isBefore(staleThreshold)) continue;
      final key = user.callsign.toLowerCase();
      final existing = byCallsign[key];
      if (existing == null || user.updatedAt.isAfter(existing.updatedAt)) {
        byCallsign[key] = user;
      }
    }
    for (final user in byCallsign.values) {
      if (_filterMission != null && user.missionCode != _filterMission && user.id != _userId) continue;
      final isMe = user.id == _userId;
      final sameMission = user.missionCode == _missionCode;
      final statusCol = _statusColor(user.status);
      final baseColor = isMe ? Colors.teal : sameMission ? Colors.blue : Colors.deepOrange;
      final ageSinceUpdate = now.difference(user.updatedAt);
      final minutesAgo = ageSinceUpdate.inMinutes;
      final timeLabel = minutesAgo < 1 ? 'now' : '${minutesAgo}m';
      final isStale = ageSinceUpdate >= kLocationStaleAfter;
      final battLabel = user.batteryLevel != null ? '🔋${user.batteryLevel}%' : '';
      // SOS highlight
      final hasSos = _activeSos.any((s) => s.userId == user.id);
      // Role icon (resource_type) and team-color ring layer on top of the
      // existing mission-relationship badge color and status border — team
      // members should read as visually grouped by color even when their
      // resource_type/icon differs, without losing the existing signals.
      final resourceType = _resourceTypeByUser[user.id] ?? '';
      final teamColor = _teamColorByUser[user.id];
      final personIcon = resourceType.isNotEmpty
          ? resourceTypeIcon(resourceType)
          : (isMe ? Icons.person_pin : Icons.person_pin_circle);
      final ringColor = teamColor ?? statusCol;
      final ringWidth = teamColor != null ? 2.5 : 1.5;
      // Fade (not remove) once past kLocationStaleAfter -- keeps the color
      // coding legible while signalling "not necessarily current."
      Color fadeIfStale(Color c) => isStale && !hasSos ? c.withValues(alpha: 0.5) : c;
      void showInfo() => showPersonnelInfoSheet(
            context,
            userId: user.id,
            callsign: user.callsign,
            resourceType: resourceType.isEmpty ? null : resourceType,
            teamName: _teamNameByUser[user.id],
            teamColor: teamColor,
            deploymentStatus: _deploymentStatusByUser[user.id],
            assignedBy: _callsign,
          );
      markers.add(Marker(
        point: LatLng(user.lat, user.lng),
        width: 100,
        height: hasSos ? 82 : 72,
        child: GestureDetector(
          onTap: showInfo,
          onLongPress: showInfo,
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
                  color: hasSos ? Colors.red : fadeIfStale(baseColor),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: hasSos ? statusCol : fadeIfStale(ringColor), width: ringWidth),
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
              Icon(personIcon,
                  color: hasSos ? Colors.red : fadeIfStale(teamColor ?? baseColor), size: 32,
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
            ],
          ),
        ),
      ));
    }

    // ── Standalone SOS markers (users not in _users — e.g. iOS devices on old builds) ──
    for (final sos in _activeSos) {
      if (_users.containsKey(sos.userId)) continue;
      markers.add(Marker(
        point: LatLng(sos.lat, sos.lng),
        width: 100,
        height: 82,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
              child: const Text('🚨 SOS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
            Container(
              constraints: const BoxConstraints(maxWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.red.shade900, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1,1))],
              ),
              child: Text(sos.callsign,
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            const Icon(Icons.person_pin_circle, color: Colors.red, size: 32,
                shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
          ],
        ),
      ));
    }

    // ── Zone labels ───────────────────────────────────────────────────────
    for (final zone in _zones) {
      if (_hiddenZoneTypes.contains(zone.zoneType)) continue;
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

    // ── Tac markers (patient, exfil, waypoints, obstacles, rally points) ───
    for (final m in _markers.values) {
      if (_hiddenMarkerTypes.contains(m.type)) continue;
      final showPill = m.type.showsLabelPill;
      final fallbackLabel = m.type == TacMarkerType.waypoint ? 'WP' : m.type.label;
      final stopIndex = _routeStops.indexWhere((s) => s.id == m.id);
      markers.add(Marker(
        point: LatLng(m.lat, m.lng),
        width: showPill ? 72 : 48,
        height: showPill ? 56 : 48,
        child: GestureDetector(
          onTap: () => _planningRoute ? _toggleRouteStop(m) : _showMarkerInfo(m),
          onLongPress: () => _confirmDeleteMarker(m),
          child: Stack(clipBehavior: Clip.none, children: [
            showPill
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: m.type.color, borderRadius: BorderRadius.circular(4)),
                      child: Text(m.label.isNotEmpty ? m.label : fallbackLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    Icon(m.type.icon, color: m.type.color, size: 28,
                        shadows: const [Shadow(color: Colors.black45, blurRadius: 3)]),
                  ])
                : Icon(m.type.icon, color: m.type.color, size: 40,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
            if (stopIndex != -1)
              Positioned(
                right: -2, top: -2,
                child: CircleAvatar(
                  radius: 9, backgroundColor: Colors.cyanAccent,
                  child: Text('${stopIndex + 1}',
                      style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
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

  Future<void> _navigateToMarker(TacMarker m) async {
    if (_myLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No GPS fix yet')));
      return;
    }
    setState(() => _isRouting = true);
    try {
      final result = await OsrmRoutingService.route(_myLocation!, LatLng(m.lat, m.lng));
      if (mounted) {
        setState(() {
          _navRoute = result;
          _navTargetLabel = m.label.isNotEmpty ? m.label : m.type.label;
          _isRouting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRouting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is RoutingException ? e.message : 'Navigation failed'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  // ── Multi-stop route planning ────────────────────────────────────────────

  void _toggleRoutePlanning() {
    setState(() {
      _planningRoute = !_planningRoute;
      if (!_planningRoute) _routeStops.clear();
      _multiRoute = null;
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

  String _stopLabel(int index) {
    if (index < 0 || index >= _routeStops.length) return '?';
    final m = _routeStops[index];
    return m.label.isNotEmpty ? m.label : m.type.label;
  }

  void _showMarkerInfo(TacMarker m) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(m.type.icon, color: m.type.color, size: 28),
              const SizedBox(width: 10),
              Text(m.type.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            if (m.label.isNotEmpty) Text(m.label, style: const TextStyle(fontSize: 14)),
            Text('Placed by ${m.placedBy}', style: TextStyle(color: Colors.grey[600])),
            Text('Reported ${formatMarkerTimestamp(m.createdAt)}', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.navigation),
                  label: const Text('Navigate Here'),
                  onPressed: () { Navigator.pop(context); _navigateToMarker(m); },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                onPressed: () { Navigator.pop(context); _confirmDeleteMarker(m); },
              ),
            ]),
          ]),
        ),
      ),
    );
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

    // ── Polylines: exfil route + waypoint route + breadcrumb trails ─────────
    final polylines = <Polyline>[];
    final extractStart = _extractionStart();
    final extractEnd   = _extractionEnd();
    if (extractStart != null && extractEnd != null) {
      polylines.add(Polyline(points: [extractStart, extractEnd],
          color: Colors.orange, strokeWidth: 3));
    }
    final waypointPts = waypointRoutePoints(_markers.values);
    if (waypointPts.length >= 2) {
      polylines.add(Polyline(points: waypointPts, color: TacMarkerType.waypoint.color, strokeWidth: 3));
    }
    if (_navRoute != null) {
      polylines.add(Polyline(points: _navRoute!.points, color: Colors.cyanAccent, strokeWidth: 4));
    }
    if (_multiRoute != null) {
      polylines.add(Polyline(points: _multiRoute!.points, color: Colors.amberAccent, strokeWidth: 4));
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
    final zoneCircles = _zones
        .where((z) => !_hiddenZoneTypes.contains(z.zoneType))
        .map((z) => CircleMarker(
            point: LatLng(z.lat, z.lng), radius: z.radiusM,
            useRadiusInMeter: true,
            color: z.color.withValues(alpha: 0.15),
            borderColor: z.color, borderStrokeWidth: 2.5))
        .toList();

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
              // Marker/zone placement (tap-to-place after picking a type from
              // the toolbar) is handled by the opaque overlays below
              // (Positioned.fill, painted on top of FlutterMap in the Stack),
              // which intercept the tap before it would ever reach here --
              // long-press below only fires when neither overlay is active.
              onLongPress: (_, point) => _onMapLongPress(point),
            ),
            children: [
              Opacity(
                // Dim base tiles when fire map is acting as the basemap
                opacity: (_fireMapAsBase && _incidentOverlay?.imageBytes != null) ? 0.0 : 1.0,
                child: TileLayer(
                  urlTemplate: _baseLayer.urlTemplate,
                  subdomains: _baseLayer == TacBaseLayer.osm
                      ? _kBaseTileSubdomains : const <String>[],
                  userAgentPackageName: 'com.resqruck.app',
                  tileProvider: _CachedTileProvider(),
                ),
              ),
              if (_incidentOverlay?.imageBytes != null)
                OverlayImageLayer(overlayImages: [
                  // RotatedOverlayImage (not OverlayImage) so filterQuality
                  // can be set -- plain OverlayImage always renders with
                  // Flutter's default low-quality bilinear filtering, which
                  // looks blocky/blurry once zoomed in past the source
                  // image's native resolution. Corners set to the bounds'
                  // NW/SW/SE produce an unrotated rectangle identical to
                  // what OverlayImage would draw.
                  RotatedOverlayImage(
                    topLeftCorner: _incidentOverlay!.bounds.northWest,
                    bottomLeftCorner: _incidentOverlay!.bounds.southWest,
                    bottomRightCorner: _incidentOverlay!.bounds.southEast,
                    imageProvider: MemoryImage(_incidentOverlay!.imageBytes!),
                    opacity: _fireMapAsBase ? 1.0 : 0.7,
                    filterQuality: FilterQuality.high,
                  ),
                ]),
              if (_incidentOverlay != null &&
                  _incidentOverlay!.polygons.isNotEmpty)
                PolygonLayer(polygons: _incidentOverlay!.polygons
                    .map((pts) => Polygon(
                          points: pts,
                          color: Colors.red.withValues(alpha: 0.20),
                          borderColor: Colors.red,
                          borderStrokeWidth: 2,
                        ))
                    .toList()),
              PolylineLayer(polylines: polylines),
              if (zoneCircles.isNotEmpty) CircleLayer(circles: zoneCircles),
              if (_showTakLayer && _takPositions.isNotEmpty)
                MarkerLayer(markers: _buildTakMarkers()),
              if (_showPoiLayer && _pois.isNotEmpty)
                MarkerLayer(markers: _buildPoiMarkers()),
              MarkerLayer(markers: _buildMapMarkers()),
            ],
          ),

          // ── SOS alert banner — one row per active SOS, each clearable on
          // its own (originator cancels their own; admin toggle resolves any) ──
          if (_activeSos.isNotEmpty)
            Positioned(top: 0, left: 0, right: 0,
              child: Material(color: Colors.red,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _activeSos.map(_buildSosRow).toList(),
                )),
            ),

          // ── Navigation banner — road route + ETA to a tapped marker ────────
          if (_isRouting)
            Positioned(
              left: 12, right: 56, bottom: _bottomChromeHeight + 8,
              child: Material(
                color: bg, borderRadius: BorderRadius.circular(8), elevation: 4,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
                    SizedBox(width: 10),
                    Text('Routing…', style: TextStyle(color: Colors.white)),
                  ]),
                ),
              ),
            )
          else if (_navRoute != null)
            Positioned(
              left: 12, right: 56, bottom: _bottomChromeHeight + 8,
              child: Material(
                color: bg, borderRadius: BorderRadius.circular(8), elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.navigation, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_navTargetLabel · ${formatDistance(_navRoute!.distanceMeters)} · ${formatDuration(_navRoute!.duration)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                      onPressed: () => setState(() { _navRoute = null; _navTargetLabel = null; }),
                    ),
                  ]),
                ),
              ),
            ),

          // ── Route planning: pick stops in order, then calculate ─────────
          if (_planningRoute)
            Positioned(
              left: 12, right: 56, bottom: _bottomChromeHeight + 8,
              child: Material(
                color: bg, borderRadius: BorderRadius.circular(8), elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _routeStops.isEmpty
                          ? 'Tap markers in order: origin, then any stops, then destination'
                          : _routeStops.map((m) => m.label.isNotEmpty ? m.label : m.type.label).join(' → '),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (_isMultiRouting)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent)),
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
              left: 12, right: 56, bottom: _bottomChromeHeight + 8,
              child: Material(
                color: bg, borderRadius: BorderRadius.circular(8), elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.alt_route, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Total: ${formatDistance(_multiRoute!.totalDistanceMeters)} · ${formatDuration(_multiRoute!.totalDuration)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () => setState(() { _multiRoute = null; _routeStops.clear(); }),
                      ),
                    ]),
                    const Divider(color: Colors.white24, height: 12),
                    for (var i = 0; i < _multiRoute!.legs.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${_stopLabel(i)} → ${_stopLabel(i + 1)}: '
                          '${formatDistance(_multiRoute!.legs[i].distanceMeters)} · '
                          '${formatDuration(_multiRoute!.legs[i].duration)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                  ]),
                ),
              ),
            ),

          // ── ATAK top header bar ─────────────────────────────────────────
          Positioned(
            top: _sosBannerHeight,
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
                if (_incidentOverlay != null && _fireMapAsBase) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() => _fireMapAsBase = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.6))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.local_fire_department, color: Colors.deepOrange, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          _incidentOverlay!.name.length > 12
                              ? '${_incidentOverlay!.name.substring(0, 12)}…'
                              : _incidentOverlay!.name,
                          style: const TextStyle(color: Colors.deepOrange, fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ]),
                    ),
                  ),
                ],
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
            top: (_sosBannerHeight) + 34,
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
            top: (_sosBannerHeight) + 34,
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
          // Height-constrained to stop above the bottom panel (rather than
          // just growing downward indefinitely) and scrollable, so every
          // button stays reachable regardless of screen height or how many
          // tools end up in this column. Collapsible via the toggle at the
          // top, since a full column of tools can otherwise run into the
          // route/nav banners lower on screen. Pinch-to-zoom already covers
          // zoom, so the +/- buttons that used to be here are gone.
          Positioned(
            right: 8,
            top: (_sosBannerHeight) + 34,
            bottom: _bottomChromeHeight + 8,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              _atakBtn(_toolsExpanded ? Icons.chevron_right : Icons.chevron_left, bg,
                  Colors.white70, () => setState(() => _toolsExpanded = !_toolsExpanded)),
              if (_toolsExpanded) ...[
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
              const SizedBox(height: 1),
              // Marker/zone visibility (hide by type — not the same as the
              // tile-layer picker below, and never deletes anything)
              _atakBtn(Icons.checklist, bg,
                  (_hiddenMarkerTypes.isNotEmpty || _hiddenZoneTypes.isNotEmpty)
                      ? Colors.amber : Colors.white54,
                  _showLayersSheet),
              const SizedBox(height: 1),
              // Multi-stop route planning: tap existing markers in order to
              // get a total ETA plus a per-segment breakdown.
              _atakBtn(Icons.alt_route, bg,
                  _planningRoute || _multiRoute != null ? Colors.amberAccent : Colors.white54,
                  _toggleRoutePlanning),
              const SizedBox(height: 6),
              // Mission filter
              _atakBtn(Icons.filter_list, bg,
                  _filterMission != null ? Colors.amber : Colors.white38,
                  _showMissionPicker),
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
              ],
            ]),
            ),
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
                  if (_placingType == TacMarkerType.waypoint) { _placeWaypoint(point); return; }
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
                  filterMission: _filterMission,
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
        const PopupMenuItem(value: 'roster',      child: Text('Mission Roster')),
        const PopupMenuItem(value: 'recenter',    child: Text('Re-centre')),
        const PopupMenuItem(value: 'status',      child: Text('My Check-in Status')),
        const PopupMenuItem(value: 'clear_routes',child: Text('Clear Routes')),
        if (_isAdmin)
          const PopupMenuItem(value: 'add_zone',  child: Text('Add Zone')),
        const PopupMenuItem(value: 'add_by_coords', child: Text('Add Marker by Coordinates')),
        const PopupMenuItem(value: 'settings',    child: Text('Supabase Settings')),
        if (_incidentOverlay?.imageBytes != null)
          PopupMenuItem(
            value: 'toggle_basemap',
            child: Text(_fireMapAsBase ? 'Show Fire Map as Overlay' : 'Use Fire Map as Basemap'),
          ),
        if (_incidentOverlay != null)
          const PopupMenuItem(value: 'clear_overlay', child: Text('Clear Fire Overlay')),
        const PopupMenuDivider(),
        // Bulk-clear per marker type — covers all types generically (not
        // just the original 3) so outdated markers of any kind can be
        // cleared in one tap instead of long-pressing each one individually.
        ...TacMarkerType.values.map((t) => PopupMenuItem(
              value: 'clear_marker_${t.name}',
              child: Text('Clear all ${t.label} markers'),
            )),
      ],
      onSelected: (v) async {
        if (v == 'roster')            _showMissionRoster();
        if (v == 'leave')             _leaveMission();
        if (v == 'join')              _joinMission();
        if (v == 'recenter' && _myLocation != null)
          _mapCtrl.move(_myLocation!, 14);
        if (v == 'status')            _pickStatus();
        if (v == 'clear_routes')      _clearRoutes();
        if (v == 'add_zone')          _startZonePlacement();
        if (v == 'add_by_coords')     _showAddByCoordinatesDialog();
        if (v == 'toggle_basemap')    setState(() => _fireMapAsBase = !_fireMapAsBase);
        if (v == 'clear_overlay')     setState(() { _incidentOverlay = null; _fireMapAsBase = false; });
        if (v.startsWith('clear_marker_')) {
          final typeName = v.substring('clear_marker_'.length);
          final type = TacMarkerType.values.firstWhere((t) => t.name == typeName, orElse: () => TacMarkerType.patient);
          _clearMarkersByType(type);
        }
        if (v == 'settings') {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => _SupabaseConfigScreen(onSaved: () => Navigator.pop(context))));
        }
      },
    );
  }

  // ── Mission Roster ────────────────────────────────────────────────────────

  void _showMissionRoster() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MissionRosterSheet(
        users: _users,
        currentUserId: _userId,
        currentMission: _missionCode,
        hasMission: _hasMission,
        onInvite: (callsign) => _sendInvite(callsign),
      ),
    );
  }

  Future<void> _sendInvite(String toCallsign) async {
    if (_missionCode.isEmpty || _callsign.isEmpty) return;
    try {
      await _supabase.from('tac_invites').insert({
        'from_callsign': _callsign,
        'to_callsign': toCallsign,
        'mission_code': _missionCode,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Invite sent to $toCallsign'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send invite: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ));
      }
    }
  }

  void _showInviteDialog(_TacInvite invite) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Mission Invite'),
        content: Text(
            '${invite.fromCallsign} invited you to join mission ${invite.missionCode}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _acceptInvite(invite);
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptInvite(_TacInvite invite) async {
    try {
      await _supabase.from('tac_invites')
          .update({'accepted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', invite.id);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMissionCode, invite.missionCode);
    await prefs.setBool(_kIsAdmin, false);
    await _reloadMissionState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Joined mission ${invite.missionCode}'),
        backgroundColor: Colors.green,
      ));
    }
  }

  // ── Field Tools ───────────────────────────────────────────────────────────

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

  void _showMissionPicker() {
    final now = DateTime.now();
    final stale = now.subtract(const Duration(minutes: 15));
    final missions = _users.values
        .where((u) => u.updatedAt.isAfter(stale) && u.missionCode.isNotEmpty)
        .map((u) => u.missionCode)
        .toSet()
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Filter by Mission',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.people, color: Colors.teal),
            title: const Text('All Missions'),
            trailing: _filterMission == null
                ? const Icon(Icons.check, color: Colors.teal)
                : null,
            selected: _filterMission == null,
            onTap: () {
              Navigator.pop(context);
              setState(() => _filterMission = null);
            },
          ),
          ...missions.map((m) {
            final count = _users.values
                .where((u) => u.missionCode == m && u.updatedAt.isAfter(stale))
                .length;
            final selected = _filterMission == m;
            return ListTile(
              leading: const Icon(Icons.task_alt, color: Colors.blue),
              title: Text(m),
              subtitle: Text('$count active'),
              trailing: selected
                  ? const Icon(Icons.check, color: Colors.blue)
                  : null,
              selected: selected,
              onTap: () {
                Navigator.pop(context);
                setState(() => _filterMission = m);
              },
            );
          }),
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
            ...TacBaseLayer.values.map((layer) => ListTile(
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
    showWildfireBrowserSheet(context, onLoad: (url, name, {bool asBase = false}) {
      Navigator.pop(context);
      _loadKmz(url, name, asBase: asBase);
    });
  }

  Future<void> _loadKmz(String url, String name, {bool asBase = false}) async {
    if (url.toLowerCase().endsWith('.pdf')) {
      return _loadPdf(url, name, asBase: asBase);
    }
    final snack = ScaffoldMessenger.of(context);
    final isLocal = url.startsWith('/') || url.startsWith('file://');
    if (!isLocal) {
      snack.showSnackBar(SnackBar(
          content: Text('Downloading $name…'),
          duration: const Duration(seconds: 30)));
    }
    try {
      final overlay = await loadWildfireKmz(url, name);
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
            content: Text('Failed to load KMZ: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4)));
      }
    }
  }

  Future<void> _loadPdf(String url, String name, {bool asBase = false}) async {
    final snack = ScaffoldMessenger.of(context);
    final isLocal = url.startsWith('/') || url.startsWith('file://');
    snack.showSnackBar(SnackBar(
        content: Text('${isLocal ? 'Loading' : 'Downloading'} $name…'),
        duration: const Duration(seconds: 60)));
    try {
      final overlay = await loadWildfirePdf(url, name);
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
            content: Text('Failed to load PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5)));
      }
    }
  }
}

class _TeamPanel extends StatefulWidget {
  final List<TacUser> users;
  final String myId;
  final String missionCode;
  final bool isAdmin;
  final String? filterMission; // null = show all missions
  final TacMarkerType? placingType;
  final ValueChanged<TacMarkerType> onPlaceType;
  final ValueChanged<String> onKickUser;

  const _TeamPanel({
    required this.users,
    required this.myId,
    required this.missionCode,
    required this.isAdmin,
    required this.filterMission,
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
    final visibleUsers = widget.filterMission == null
        ? widget.users
        : widget.users.where((u) =>
            u.missionCode == widget.filterMission || u.id == widget.myId).toList();

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              widget.filterMission == null ? 'ALL MISSIONS' : 'MISSION — ${widget.filterMission}',
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
    final label = widget.filterMission == null && u.missionCode != widget.missionCode
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

// ── Mission Roster Sheet ──────────────────────────────────────────────────────

class _MissionRosterSheet extends StatelessWidget {
  final Map<String, TacUser> users;
  final String currentUserId;
  final String currentMission;
  final bool hasMission;
  final void Function(String callsign) onInvite;

  const _MissionRosterSheet({
    required this.users,
    required this.currentUserId,
    required this.currentMission,
    required this.hasMission,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Group users by mission_code
    final Map<String, List<TacUser>> byMission = {};
    for (final u in users.values) {
      byMission.putIfAbsent(u.missionCode, () => []).add(u);
    }

    // Sort: current mission first, then named missions, then no-mission last
    final missions = byMission.keys.toList()
      ..sort((a, b) {
        if (a == currentMission) return -1;
        if (b == currentMission) return 1;
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Column(children: [
        // Handle
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(children: [
            const Icon(Icons.groups, size: 20),
            const SizedBox(width: 8),
            const Text('Mission Roster',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${users.length} online',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: missions.isEmpty
              ? const Center(child: Text('No users online'))
              : ListView.builder(
                  controller: ctrl,
                  itemCount: missions.length,
                  itemBuilder: (_, i) {
                    final code = missions[i];
                    final members = List<TacUser>.from(byMission[code]!)
                      ..sort((a, b) {
                        final aOn = now.difference(a.updatedAt).inMinutes < 3;
                        final bOn = now.difference(b.updatedAt).inMinutes < 3;
                        if (aOn != bOn) return aOn ? -1 : 1;
                        return a.callsign.compareTo(b.callsign);
                      });

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mission header
                        Container(
                          color: (code == currentMission)
                              ? Colors.blue.withValues(alpha: 0.08)
                              : null,
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Row(children: [
                            Icon(
                              code.isEmpty ? Icons.person_outline : Icons.flag,
                              size: 15,
                              color: code == currentMission
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              code.isEmpty ? 'No Mission' : code,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: code == currentMission
                                    ? Colors.blue
                                    : Colors.grey[700],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('(${members.length})',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 12)),
                            if (code == currentMission) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('YOUR MISSION',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              ),
                            ],
                          ]),
                        ),
                        // Members
                        ...members.map((u) {
                          final isOnline =
                              now.difference(u.updatedAt).inMinutes < 3;
                          final isMe = u.id == currentUserId;
                          final alreadyInMission =
                              hasMission && u.missionCode == currentMission;
                          final canInvite = hasMission && !isMe;
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            leading: Stack(clipBehavior: Clip.none, children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isOnline
                                    ? const Color(0xFF1565C0)
                                    : Colors.grey,
                                child: Text(
                                  u.callsign.isNotEmpty
                                      ? u.callsign[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              Positioned(
                                bottom: 0, right: -2,
                                child: Container(
                                  width: 10, height: 10,
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? Colors.greenAccent[400]
                                        : Colors.grey[400],
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                            ]),
                            title: Text(
                              u.callsign + (isMe ? '  (you)' : ''),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isOnline ? null : Colors.grey),
                            ),
                            subtitle: Text(
                              isOnline
                                  ? u.status
                                  : _rosterAgo(u.updatedAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isOnline
                                      ? Colors.green[700]
                                      : Colors.grey),
                            ),
                            trailing: isMe
                                ? null
                                : alreadyInMission
                                    ? const Text('In mission',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey))
                                    : canInvite
                                        ? TextButton.icon(
                                            icon: const Icon(
                                                Icons.person_add, size: 16),
                                            label: const Text('Invite'),
                                            onPressed: () {
                                              Navigator.pop(context);
                                              onInvite(u.callsign);
                                            },
                                          )
                                        : null,
                          );
                        }),
                        const Divider(height: 1),
                      ],
                    );
                  },
                ),
        ),
      ]),
    );
  }

  static String _rosterAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
