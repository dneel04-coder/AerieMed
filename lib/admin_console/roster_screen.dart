import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../tac_map.dart' show TacUser, kResourceTypes;
import '../incident_service.dart';
import '../asset_service.dart';

enum _RosterMode { allUsers, thisIncident }

/// A row from `user_profiles` — the full directory of everyone who's ever
/// logged in, independent of whether they've ever opened Tac Map.
class _DirectoryUser {
  final String userId;
  final String name;
  final String callsign;
  final String resourceType;
  final String? teamId;
  final String deploymentStatus;
  const _DirectoryUser({
    required this.userId,
    required this.name,
    required this.callsign,
    this.resourceType = '',
    this.teamId,
    this.deploymentStatus = 'Standby',
  });
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
  List<Team> _teams = [];
  Map<String, List<Asset>> _assetsByUser = {}; // userId -> assigned assets
  bool _loading = true;
  late _RosterMode _mode;
  final _searchCtrl = TextEditingController();
  final Set<String> _expandedAssets = {};

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
    var teams = <Team>[];
    var assetsByUser = <String, List<Asset>>{};

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
                resourceType: m['resource_type'] as String? ?? '',
                teamId: m['team_id'] as String?,
                deploymentStatus: m['deployment_status'] as String? ?? 'Standby',
              );
            })
            .where((u) => u.userId.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    teams = await AssetService.instance.fetchTeams();
    try {
      final activeAssignments = await AssetService.instance.fetchActiveAssignments();
      final userAssignments = activeAssignments.where((a) => a.assignableType == AssignableType.user).toList();
      if (userAssignments.isNotEmpty) {
        final allAssets = await AssetService.instance.fetchAssets();
        final assetById = {for (final a in allAssets) a.id: a};
        for (final assignment in userAssignments) {
          final asset = assetById[assignment.assetId];
          if (asset == null) continue;
          assetsByUser.putIfAbsent(assignment.assignableId, () => []).add(asset);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _members = members;
        _online = online;
        _allOnline = allOnline;
        _directory = directory;
        _teams = teams;
        _assetsByUser = assetsByUser;
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

  Future<void> _assignAsset(_DirectoryUser user) async {
    final asset = await showModalBottomSheet<Asset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AssetPickerSheet(),
    );
    if (asset == null) return;
    try {
      await AssetService.instance.assignAssetToUser(asset.id, user.userId, assignedBy: 'Command Console');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Assigned ${asset.identifier} to ${user.display}.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign asset: $e')));
      }
    }
  }

  Future<void> _assignTeam(_DirectoryUser user) async {
    final team = await showModalBottomSheet<Team>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TeamPickerSheet(teams: _teams),
    );
    if (team == null) return;
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').update({'team_id': team.id}).eq('user_id', user.userId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Assigned ${user.display} to ${team.name}.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign team: $e')));
      }
    }
  }

  Future<void> _setResourceType(_DirectoryUser user) async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Resource Type — ${user.display}'),
        children: kResourceTypes
            .map((t) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Text(t)))
            .toList(),
      ),
    );
    if (type == null) return;
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').update({'resource_type': type}).eq('user_id', user.userId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not set resource type: $e')));
      }
    }
  }

  Future<void> _setDeploymentStatus(_DirectoryUser user) async {
    final status = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Status — ${user.display}'),
        children: kDeploymentStatuses
            .map((s) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, s), child: Text(s)))
            .toList(),
      ),
    );
    if (status == null) return;
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').update({'deployment_status': status}).eq('user_id', user.userId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not set status: $e')));
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

  Color _statusColor(String status) => switch (status) {
        'On Mission' => Colors.blue,
        'In Transit' => Colors.orange,
        'Off Duty' => Colors.grey,
        _ => Colors.green, // Standby
      };

  /// Shared row for a person, used by both All Users and This Incident
  /// lists — online dot, name, team/status/resource-type subtitle, quick
  /// actions (assign asset / team / resource type / status), and an
  /// expandable section listing currently-assigned assets.
  Widget _personCard({
    required String userId,
    required String display,
    required bool isOnline,
    required String subtitleExtra,
    _DirectoryUser? directoryUser,
    Widget? trailingAction,
  }) {
    final teamName = directoryUser?.teamId == null
        ? null
        : _teams.where((t) => t.id == directoryUser!.teamId).map((t) => t.name).firstOrNull;
    final assets = _assetsByUser[userId] ?? const <Asset>[];
    final isExpanded = _expandedAssets.contains(userId);
    final subtitleParts = <String>[
      subtitleExtra,
      if (directoryUser != null && directoryUser.resourceType.isNotEmpty) directoryUser.resourceType,
      if (teamName != null) teamName,
    ];

    return Card(
      child: Column(children: [
        ListTile(
          leading: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 12, color: isOnline ? Colors.green : Colors.grey),
            if (directoryUser != null) ...[
              const SizedBox(height: 4),
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: _statusColor(directoryUser.deploymentStatus)),
              ),
            ],
          ]),
          title: Text(display),
          subtitle: Text(subtitleParts.join(' • ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (trailingAction != null) trailingAction,
            if (directoryUser != null)
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'asset':
                      _assignAsset(directoryUser);
                    case 'team':
                      _assignTeam(directoryUser);
                    case 'resource_type':
                      _setResourceType(directoryUser);
                    case 'status':
                      _setDeploymentStatus(directoryUser);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'asset', child: Text('Assign Asset')),
                  PopupMenuItem(value: 'team', child: Text('Assign to Team')),
                  PopupMenuItem(value: 'resource_type', child: Text('Set Resource Type')),
                  PopupMenuItem(value: 'status', child: Text('Set Status')),
                ],
              ),
            if (assets.isNotEmpty)
              IconButton(
                icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                tooltip: isExpanded ? 'Hide assets' : 'Show assets (${assets.length})',
                onPressed: () => setState(() {
                  if (isExpanded) {
                    _expandedAssets.remove(userId);
                  } else {
                    _expandedAssets.add(userId);
                  }
                }),
              ),
          ]),
        ),
        if (isExpanded && assets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: assets
                    .map((a) => Chip(
                          avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                          label: Text('${a.identifier} (${a.type})'),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ),
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
          return _personCard(
            userId: u.userId,
            display: u.display,
            isOnline: loc != null,
            subtitleExtra: loc != null
                ? 'Online — mission ${loc.missionCode.isEmpty ? '(none)' : loc.missionCode}'
                : 'Offline — no current location',
            directoryUser: u,
            trailingAction: incident == null
                ? null
                : FilledButton.tonal(
                    onPressed: () => _assignToIncident(u),
                    child: const Text('Assign'),
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
    final directoryById = {for (final u in _directory) u.userId: u};

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('On this incident (${_members.where((m) => m.isActive).length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._members.where((m) => m.isActive).map((m) {
          final isOnline = _online.any((u) => u.id == m.userId);
          return _personCard(
            userId: m.userId,
            display: m.callsign.isEmpty ? m.userId : m.callsign,
            isOnline: isOnline,
            subtitleExtra: m.isPending
                ? 'Assigned — waiting on them to accept'
                : (isOnline ? 'Online' : 'Offline — not currently broadcasting'),
            directoryUser: directoryById[m.userId],
            trailingAction: IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Remove from incident',
              onPressed: () => _removeMember(m),
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

/// Picks an unassigned asset, optionally filtered by type — used by
/// Roster's "Assign Asset" action so admins can hand out equipment to
/// standby/in-transit personnel without going through an incident.
class _AssetPickerSheet extends StatefulWidget {
  const _AssetPickerSheet();
  @override
  State<_AssetPickerSheet> createState() => _AssetPickerSheetState();
}

class _AssetPickerSheetState extends State<_AssetPickerSheet> {
  List<Asset> _assets = [];
  bool _loading = true;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final assets = await AssetService.instance.fetchUnassignedAssets(type: _typeFilter);
    if (mounted) setState(() { _assets = assets; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign Asset', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All types')),
              ...{for (final a in _assets) a.type}
                  .followedBy(_typeFilter != null ? [_typeFilter!] : [])
                  .toSet()
                  .map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
            ],
            onChanged: (v) => setState(() { _typeFilter = v; _load(); }),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _assets.isEmpty
                    ? Center(child: Text('No unassigned assets.', style: TextStyle(color: Colors.grey[600])))
                    : ListView.builder(
                        itemCount: _assets.length,
                        itemBuilder: (_, i) {
                          final a = _assets[i];
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
      ),
    );
  }
}

/// Picks a team, or creates a new one inline — used by Roster's "Assign to
/// Team" action.
class _TeamPickerSheet extends StatefulWidget {
  final List<Team> teams;
  const _TeamPickerSheet({required this.teams});
  @override
  State<_TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends State<_TeamPickerSheet> {
  late List<Team> _teams;
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  String _designation = kTeamDesignations.first;

  @override
  void initState() {
    super.initState();
    _teams = widget.teams;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      final team = await AssetService.instance.createTeam(name: name, designation: _designation);
      if (team != null && mounted) Navigator.pop(context, team);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create team: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign to Team', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (!_creating) ...[
            SizedBox(
              height: 260,
              child: _teams.isEmpty
                  ? Center(child: Text('No teams yet.', style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      itemCount: _teams.length,
                      itemBuilder: (_, i) {
                        final t = _teams[i];
                        return ListTile(
                          leading: const Icon(Icons.groups),
                          title: Text(t.name),
                          subtitle: t.designation.isEmpty ? null : Text(t.designation),
                          onTap: () => Navigator.pop(context, t),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _creating = true),
              icon: const Icon(Icons.add),
              label: const Text('New Team'),
            ),
          ] else ...[
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Team name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _designation,
              decoration: const InputDecoration(labelText: 'Designation', border: OutlineInputBorder()),
              items: kTeamDesignations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setState(() => _designation = v ?? _designation),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _creating = false),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: _create, child: const Text('Create & Assign')),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}
