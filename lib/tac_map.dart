import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;

// ─── Supabase config keys ────────────────────────────────────────────────────
const _kSupabaseUrl = 'tac_supabase_url';
const _kSupabaseKey = 'tac_supabase_anon_key';
const _kCallsign = 'tac_callsign';
const _kMissionCode = 'tac_mission_code';
const _kIsAdmin = 'tac_is_admin';
const _kUserId = 'tac_user_id';

// ─── Models ──────────────────────────────────────────────────────────────────
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
  final double lat;
  final double lng;
  final bool isAdmin;
  final DateTime updatedAt;

  TacUser({
    required this.id,
    required this.callsign,
    required this.lat,
    required this.lng,
    required this.isAdmin,
    required this.updatedAt,
  });

  factory TacUser.fromMap(Map<String, dynamic> m) => TacUser(
        id: m['id'] as String,
        callsign: m['callsign'] as String,
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

// ─── Entry point ─────────────────────────────────────────────────────────────
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

// ─── Supabase config screen ───────────────────────────────────────────────────
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
create table tac_users (
  id text not null,
  mission_code text not null,
  callsign text not null,
  lat double precision not null,
  lng double precision not null,
  is_admin boolean default false,
  updated_at timestamptz default now(),
  primary key (id, mission_code)
);
create table tac_markers (
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
create policy "public_access" on tac_users
  for all using (true) with check (true);
create policy "public_access" on tac_markers
  for all using (true) with check (true);
alter publication supabase_realtime add table tac_users;
alter publication supabase_realtime add table tac_markers;''';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(_sql, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    );
  }
}

// ─── Mission setup screen ─────────────────────────────────────────────────────
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

// ─── Active map screen ────────────────────────────────────────────────────────
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

  StreamSubscription<List<Map<String, dynamic>>>? _userSub;
  StreamSubscription<List<Map<String, dynamic>>>? _markerSub;
  Timer? _locationTimer;

  bool _mapReady = false;
  LatLng? _myLocation;
  TacMarkerType? _placingType;

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
    _userSub = _supabase
        .from('tac_users')
        .stream(primaryKey: ['id', 'mission_code'])
        .eq('mission_code', _missionCode)
        .listen((rows) {
          if (!mounted) return;
          setState(() {
            _users.clear();
            for (final r in rows) {
              final u = TacUser.fromMap(r);
              _users[u.id] = u;
            }
          });
        });

    _markerSub = _supabase
        .from('tac_markers')
        .stream(primaryKey: ['id'])
        .eq('mission_code', _missionCode)
        .listen((rows) {
          if (!mounted) return;
          setState(() {
            _markers.clear();
            for (final r in rows) {
              final m = TacMarker.fromMap(r);
              _markers[m.id] = m;
            }
          });
        });
  }

  Future<void> _loadInitialData() async {
    try {
      final users = await _supabase
          .from('tac_users')
          .select()
          .eq('mission_code', _missionCode);
      final markers = await _supabase
          .from('tac_markers')
          .select()
          .eq('mission_code', _missionCode);
      if (!mounted) return;
      setState(() {
        for (final r in users as List) {
          final u = TacUser.fromMap(r as Map<String, dynamic>);
          _users[u.id] = u;
        }
        for (final r in markers as List) {
          final m = TacMarker.fromMap(r as Map<String, dynamic>);
          _markers[m.id] = m;
        }
      });
    } catch (_) {}
  }

  Future<void> _placeMarker(LatLng pos, TacMarkerType type) async {
    try {
      await _supabase.from('tac_markers').insert({
        'mission_code': _missionCode,
        'type': type.name,
        'label': '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'placed_by': _callsign,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
    setState(() => _placingType = null);
  }

  Future<void> _deleteMarker(String id) async {
    try {
      await _supabase.from('tac_markers').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> _leaveMission() async {
    _locationTimer?.cancel();
    _userSub?.cancel();
    _markerSub?.cancel();
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
    _userSub?.cancel();
    _markerSub?.cancel();
    super.dispose();
  }

  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];

    for (final user in _users.values) {
      final isMe = user.id == _userId;
      markers.add(Marker(
        point: LatLng(user.lat, user.lng),
        width: 56,
        height: 56,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isMe ? Colors.teal : Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(user.callsign,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            Icon(isMe ? Icons.person_pin : Icons.person_pin_circle,
                color: isMe ? Colors.teal : Colors.blue, size: 28),
          ],
        ),
      ));
    }

    for (final m in _markers.values) {
      markers.add(Marker(
        point: LatLng(m.lat, m.lng),
        width: 44,
        height: 44,
        child: GestureDetector(
          onLongPress: () => _confirmDeleteMarker(m),
          child: Icon(m.type.icon, color: m.type.color, size: 36),
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
          PopupMenuButton(itemBuilder: (_) => [
            const PopupMenuItem(value: 'leave', child: Text('Leave Mission')),
            const PopupMenuItem(value: 'recenter', child: Text('Re-center')),
          ], onSelected: (v) {
            if (v == 'leave') _leaveMission();
            if (v == 'recenter' && _myLocation != null) _mapCtrl.move(_myLocation!, 14);
          }),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _myLocation ?? const LatLng(37.0902, -95.7129),
                initialZoom: _myLocation != null ? 14 : 4,
                onMapReady: () {
                  _mapReady = true;
                  if (_myLocation != null) _mapCtrl.move(_myLocation!, 14);
                },
                onLongPress: _placingType != null
                    ? (_, point) => _placeMarker(point, _placingType!)
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.aerie.aerimed1',
                ),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: _buildMapMarkers()),
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
}

// ─── Team panel ───────────────────────────────────────────────────────────────
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              ...TacMarkerType.values.map((t) {
                final active = placingType == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.icon, size: 14, color: active ? Colors.white : t.color),
                        const SizedBox(width: 4),
                        Text(t.label, style: TextStyle(fontSize: 11, color: active ? Colors.white : null)),
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
              }),
            ],
          ),
          if (placingType != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Long-press on the map to place ${placingType!.label} marker. Tap chip again to cancel.',
                style: TextStyle(fontSize: 11, color: placingType!.color, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}
