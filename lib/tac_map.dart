import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;

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
  extractionEnd;

  String get label => switch (this) {
        patient => 'Patient',
        extractionStart => 'Extract Start',
        extractionEnd => 'Extract End',
      };

  Color get color => switch (this) {
        patient => Colors.red,
        extractionStart => Colors.orange,
        extractionEnd => Colors.green,
      };

  IconData get icon => switch (this) {
        patient => Icons.personal_injury,
        extractionStart => Icons.flag,
        extractionEnd => Icons.local_hospital,
      };
}

class TacUser {
  final String id;
  final String callsign;
  final String missionCode;
  final double lat;
  final double lng;
  final bool isAdmin;
  final DateTime updatedAt;

  TacUser({
    required this.id,
    required this.callsign,
    required this.missionCode,
    required this.lat,
    required this.lng,
    required this.isAdmin,
    required this.updatedAt,
  });

  factory TacUser.fromMap(Map<String, dynamic> m) => TacUser(
        id: m['id'] as String,
        callsign: m['callsign'] as String,
        missionCode: m['mission_code'] as String? ?? '',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        isAdmin: m['is_admin'] as bool? ?? false,
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
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
    final url = prefs.getString(_kSupabaseUrl) ?? '';
    final key = prefs.getString(_kSupabaseKey) ?? '';

    if (url.isEmpty || key.isEmpty) {
      setState(() => _phase = _Phase.noConfig);
      return;
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
  void _onSessionJoined() => setState(() => _phase = _Phase.active);
  void _onLeft() => setState(() => _phase = _Phase.noSession);

  @override
  Widget build(BuildContext context) => switch (_phase) {
        _Phase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        _Phase.noConfig => _SupabaseConfigScreen(onSaved: _onConfigSaved),
        _Phase.noSession => _MissionSetupScreen(onJoined: _onSessionJoined),
        _Phase.active => _ActiveMapScreen(onLeft: _onLeft),
      };
}

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

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseUrl, url);
    await prefs.setString(_kSupabaseKey, key);
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
      appBar: AppBar(title: const Text('Tac Map — Supabase Config')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Tac Map requires a Supabase project for real-time location sharing. '
            'Create a free project at supabase.com, then run the SQL below in the SQL Editor.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          _SqlBlock(),
          const SizedBox(height: 24),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Project URL',
              hintText: 'https://xxxx.supabase.co',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(
              labelText: 'Anon Public Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save & Connect'),
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

    await _requestLocation();
    _startLocationPublish();
    _subscribeRealtime();
    _loadInitialData();
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

  Future<void> _publishLocation() async {
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
          id: _userId,
          callsign: _callsign,
          missionCode: _missionCode,
          lat: _myLocation!.latitude,
          lng: _myLocation!.longitude,
          isAdmin: _isAdmin,
          updatedAt: DateTime.now(),
        );
      });
    }
    try {
      await _supabase.from('tac_users').upsert({
        'id': _userId,
        'mission_code': _missionCode,
        'callsign': _callsign,
        'lat': _myLocation!.latitude,
        'lng': _myLocation!.longitude,
        'is_admin': _isAdmin,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
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
                setState(() => _users[u.id] = u);
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
        .subscribe();
    // Periodic fallback re-fetch in case any realtime events are missed
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
          _users[u.id] = u;
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
        content: Text(msg),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 8),
      ));
    }
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
    try {
      await _supabase.from('tac_markers').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> _leaveMission() async {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    try {
      await _supabase
          .from('tac_users')
          .delete()
          .eq('id', _userId)
          .eq('mission_code', _missionCode);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCallsign);
    await prefs.remove(_kMissionCode);
    await prefs.remove(_kIsAdmin);
    widget.onLeft();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _refreshTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];

    for (final user in _users.values) {
      final isMe = user.id == _userId;
      final sameMission = user.missionCode == _missionCode;
      final color = isMe
          ? Colors.teal
          : sameMission
              ? Colors.blue
              : Colors.deepOrange;
      // Label: callsign + mission code for users on other missions
      final label = sameMission ? user.callsign : '${user.callsign}\n${user.missionCode}';
      markers.add(Marker(
        point: LatLng(user.lat, user.lng),
        width: 88,
        height: sameMission ? 60 : 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 1))],
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            Icon(isMe ? Icons.person_pin : Icons.person_pin_circle,
                color: color, size: 34,
                shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
          ],
        ),
      ));
    }

    for (final m in _markers.values) {
      markers.add(Marker(
        point: LatLng(m.lat, m.lng),
        width: 48,
        height: 48,
        child: GestureDetector(
          onLongPress: () => _confirmDeleteMarker(m),
          child: Icon(m.type.icon, color: m.type.color, size: 40,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
        ),
      ));
    }

    return markers;
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
    final extractStart = _extractionStart();
    final extractEnd = _extractionEnd();

    final polylines = <Polyline>[];
    if (extractStart != null && extractEnd != null) {
      polylines.add(Polyline(
        points: [extractStart, extractEnd],
        color: Colors.orange,
        strokeWidth: 3,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('TAC MAP — $_missionCode'),
        actions: [
          if (_isAdmin)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('ADMIN', style: TextStyle(fontSize: 10)),
                backgroundColor: Colors.orange,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Map Layers',
            onPressed: _showLayerPicker,
          ),
          IconButton(
            icon: const Icon(Icons.local_fire_department),
            tooltip: 'Wildfire Incident Maps',
            onPressed: _showIncidentBrowser,
          ),
          PopupMenuButton(itemBuilder: (_) => [
            const PopupMenuItem(value: 'leave', child: Text('Leave Mission')),
            const PopupMenuItem(value: 'recenter', child: Text('Re-center')),
            const PopupMenuItem(value: 'supabase_settings', child: Text('Supabase Settings / SQL')),
            if (_incidentOverlay != null)
              const PopupMenuItem(value: 'clear_overlay', child: Text('Clear Incident Overlay')),
          ], onSelected: (v) async {
            if (v == 'leave') _leaveMission();
            if (v == 'recenter' && _myLocation != null) _mapCtrl.move(_myLocation!, 14);
            if (v == 'clear_overlay') setState(() => _incidentOverlay = null);
            if (v == 'supabase_settings') {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => _SupabaseConfigScreen(onSaved: () => Navigator.pop(context)),
              ));
            }
          }),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _myLocation ?? const LatLng(37.0902, -95.7129),
                    initialZoom: _myLocation != null ? 14 : 4,
                    onMapReady: () {
                      _mapReady = true;
                      if (_myLocation != null) _mapCtrl.move(_myLocation!, 14);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _baseLayer.urlTemplate,
                      userAgentPackageName: 'com.aerie.aerimed',
                    ),
                    if (_incidentOverlay != null)
                      OverlayImageLayer(
                        overlayImages: [
                          OverlayImage(
                            bounds: _incidentOverlay!.bounds,
                            imageProvider: MemoryImage(_incidentOverlay!.imageBytes),
                            opacity: 0.7,
                          ),
                        ],
                      ),
                    PolylineLayer(polylines: polylines),
                    MarkerLayer(markers: _buildMapMarkers()),
                  ],
                ),
                // Placement overlay — sits above the map and captures taps
                // directly, bypassing flutter_map's gesture arena entirely.
                if (_placingType != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        if (!_mapReady) return;
                        final point = _mapCtrl.camera.pointToLatLng(
                          Point(
                            details.localPosition.dx,
                            details.localPosition.dy,
                          ),
                        );
                        _placeMarker(point, _placingType!);
                      },
                      child: Container(
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_placingType!.icon,
                                color: _placingType!.color, size: 52),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: _placingType!.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Tap map to place ${_placingType!.label}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _TeamPanel(
            users: _users.values.toList(),
            myId: _userId,
            placingType: _placingType,
            onPlaceType: (t) => setState(() => _placingType = _placingType == t ? null : t),
          ),
        ],
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

class _TeamPanel extends StatelessWidget {
  final List<TacUser> users;
  final String myId;
  final TacMarkerType? placingType;
  final ValueChanged<TacMarkerType> onPlaceType;

  const _TeamPanel({
    required this.users,
    required this.myId,
    required this.placingType,
    required this.onPlaceType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('TEAM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: users.map((u) {
                      final isMe = u.id == myId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          label: Text(u.callsign,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isMe ? Colors.white : null,
                                  fontWeight: isMe ? FontWeight.bold : null)),
                          backgroundColor: isMe ? Colors.teal : null,
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('PLACE:', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: TacMarkerType.values.map((t) {
                      final active = placingType == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t.icon, size: 14, color: active ? Colors.white : t.color),
                              const SizedBox(width: 4),
                              Text(t.label,
                                  style: TextStyle(
                                      fontSize: 11, color: active ? Colors.white : null)),
                            ],
                          ),
                          selected: active,
                          onSelected: (_) => onPlaceType(t),
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
            ],
          ),
          if (placingType != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tap the map to place ${placingType!.label} marker. Tap chip again to cancel.',
                style: TextStyle(
                    fontSize: 11, color: placingType!.color, fontStyle: FontStyle.italic),
              ),
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
