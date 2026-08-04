import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../tac_map.dart' show TacUser;
import '../incident_service.dart';

enum _RosterMode { allUsers, thisIncident }

/// A row from `user_profiles` — the full directory of everyone who's ever
/// logged in, independent of whether they've ever opened Tac Map.
class _DirectoryUser {
  final String userId;
  final String name;
  final String callsign;
  const _DirectoryUser({required this.userId, required this.name, required this.callsign});
  String get display => callsign.isNotEmpty ? callsign : (name.isNotEmpty ? name : userId);
}

class RosterScreen extends StatefulWidget {
  final TacIncident? incident;
  const RosterScreen({super.key, required this.incident});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  List<IncidentMember> _members = [];
  List<TacUser> _online = []; // scoped to this incident's mission_code
  List<TacUser> _allOnline = []; // unfiltered, across every mission
  List<_DirectoryUser> _directory = [];
  bool _loading = true;
  late _RosterMode _mode;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mode = widget.incident == null ? _RosterMode.allUsers : _RosterMode.thisIncident;
    _load();
  }

  @override
  void didUpdateWidget(covariant RosterScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.id != widget.incident?.id) {
      if (widget.incident == null) _mode = _RosterMode.allUsers;
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final incident = widget.incident;
    final client = SupabaseService.client;

    var members = <IncidentMember>[];
    var online = <TacUser>[];
    var allOnline = <TacUser>[];
    var directory = <_DirectoryUser>[];

    if (incident != null) {
      members = await IncidentService.instance.fetchMembers(incident.id);
    }
    if (client != null) {
      if (incident != null) {
        try {
          final rows = await client
              .from('tac_users')
              .select()
              .eq('mission_code', incident.missionCode) as List;
          online = rows.map((r) => TacUser.fromMap(r as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      try {
        final rows = await client.from('tac_users').select() as List;
        final seen = <String>{};
        allOnline = rows
            .map((r) => TacUser.fromMap(r as Map<String, dynamic>))
            .where((u) => seen.add(u.id)) // dedupe by id across missions
            .toList();
      } catch (_) {}
      try {
        final rows = await client.from('user_profiles').select() as List;
        directory = rows
            .map((r) {
              final m = r as Map<String, dynamic>;
              return _DirectoryUser(
                userId: m['user_id'] as String? ?? '',
                name: m['name'] as String? ?? '',
                callsign: m['callsign'] as String? ?? '',
              );
            })
            .where((u) => u.userId.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _members = members;
        _online = online;
        _allOnline = allOnline;
        _directory = directory;
        _loading = false;
      });
    }
  }

  Future<void> _addOnlineUser(TacUser user) async {
    final incident = widget.incident;
    if (incident == null) return;
    try {
      await IncidentService.instance.addMember(incident.id, userId: user.id, callsign: user.callsign);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add to roster: $e')));
      }
    }
  }

  Future<void> _assignToIncident(_DirectoryUser user) async {
    final incident = widget.incident;
    if (incident == null) return;
    try {
      await IncidentService.instance.addMember(incident.id, userId: user.userId, callsign: user.display);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Assigned ${user.display} — they\'ll get a prompt to accept in the app.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign: $e')));
      }
    }
  }

  Future<void> _removeMember(IncidentMember member) async {
    try {
      await IncidentService.instance.markMemberLeft(member.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update roster: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<_RosterMode>(
            segments: const [
              ButtonSegment(value: _RosterMode.allUsers, label: Text('All Users'), icon: Icon(Icons.groups)),
              ButtonSegment(
                  value: _RosterMode.thisIncident,
                  label: Text('This Incident'),
                  icon: Icon(Icons.local_fire_department)),
            ],
            selected: {_mode},
            onSelectionChanged: widget.incident == null ? null : (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _mode == _RosterMode.allUsers
                  ? _buildAllUsers()
                  : _buildThisIncident(),
        ),
      ]),
    );
  }

  Widget _buildAllUsers() {
    final onlineById = {for (final u in _allOnline) u.id: u};
    final incident = widget.incident;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _directory
        : _directory.where((u) => u.display.toLowerCase().contains(query)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            hintText: 'Search by name or callsign…',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text('All known users (${filtered.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...filtered.map((u) {
          final loc = onlineById[u.userId];
          return Card(
            child: ListTile(
              leading: Icon(Icons.circle, size: 12, color: loc != null ? Colors.green : Colors.grey),
              title: Text(u.display),
              subtitle: Text(loc != null
                  ? 'Online — mission ${loc.missionCode.isEmpty ? '(none)' : loc.missionCode}'
                  : 'Offline — no current location'),
              trailing: incident == null
                  ? null
                  : FilledButton.tonal(
                      onPressed: () => _assignToIncident(u),
                      child: const Text('Assign'),
                    ),
            ),
          );
        }),
        if (_directory.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(child: Text('No users found yet.', style: TextStyle(color: Colors.grey[600]))),
          ),
      ],
    );
  }

  Widget _buildThisIncident() {
    final incident = widget.incident;
    if (incident == null) return const SizedBox.shrink();
    final memberUserIds = _members.where((m) => m.isActive).map((m) => m.userId).toSet();
    final unattached = _online.where((u) => !memberUserIds.contains(u.id)).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('On this incident (${_members.where((m) => m.isActive).length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._members.where((m) => m.isActive).map((m) {
          final isOnline = _online.any((u) => u.id == m.userId);
          return Card(
            child: ListTile(
              leading: Icon(Icons.circle, size: 12, color: isOnline ? Colors.green : Colors.grey),
              title: Text(m.callsign.isEmpty ? m.userId : m.callsign),
              subtitle: Text(m.isPending
                  ? 'Assigned — waiting on them to accept'
                  : (isOnline ? 'Online' : 'Offline — not currently broadcasting')),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove from incident',
                onPressed: () => _removeMember(m),
              ),
            ),
          );
        }),
        if (unattached.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Online on this mission code, not yet added (${unattached.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...unattached.map((u) => Card(
                child: ListTile(
                  leading: const Icon(Icons.circle, size: 12, color: Colors.green),
                  title: Text(u.callsign),
                  subtitle: Text('Battery: ${u.batteryLevel ?? '—'}% • ${u.status}'),
                  trailing: FilledButton.tonal(
                    onPressed: () => _addOnlineUser(u),
                    child: const Text('Add'),
                  ),
                ),
              )),
        ],
        if (_members.isEmpty && unattached.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text('No one has joined mission code ${incident.missionCode} yet.',
                  style: TextStyle(color: Colors.grey[600])),
            ),
          ),
      ],
    );
  }
}
