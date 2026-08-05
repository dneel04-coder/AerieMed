import 'package:flutter/material.dart';
import '../asset_service.dart';
import '../incident_service.dart' show IncidentService;
import '../protocol_admin.dart' show SupabaseService;

/// Lightweight ops screen for reassigning/unassigning equipment without
/// going through the map — a searchable/filterable list of every asset with
/// its current assignment status.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  List<Asset> _assets = [];
  Map<String, AssetAssignment> _activeByAsset = {}; // assetId -> active assignment
  Map<String, String> _userNameById = {};
  Map<String, String> _teamNameById = {};
  Map<String, String> _missionNameById = {};
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String? _typeFilter;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final assets = await AssetService.instance.fetchAssets();
    final activeAssignments = await AssetService.instance.fetchActiveAssignments();
    final activeByAsset = {for (final a in activeAssignments) a.assetId: a};

    final userNameById = <String, String>{};
    final client = SupabaseService.client;
    if (client != null) {
      try {
        final rows = await client.from('user_profiles').select('user_id, name, callsign') as List;
        for (final r in rows) {
          final m = r as Map<String, dynamic>;
          final id = m['user_id'] as String? ?? '';
          if (id.isEmpty) continue;
          final callsign = m['callsign'] as String? ?? '';
          final name = m['name'] as String? ?? '';
          userNameById[id] = callsign.isNotEmpty ? callsign : (name.isNotEmpty ? name : id);
        }
      } catch (_) {}
    }
    final teams = await AssetService.instance.fetchTeams();
    final teamNameById = {for (final t in teams) t.id: t.name};
    final incidents = await IncidentService.instance.fetchIncidents();
    final missionNameById = {for (final i in incidents) i.id: (i.name.isEmpty ? i.missionCode : i.name)};

    if (mounted) {
      setState(() {
        _assets = assets;
        _activeByAsset = activeByAsset;
        _userNameById = userNameById;
        _teamNameById = teamNameById;
        _missionNameById = missionNameById;
        _loading = false;
      });
    }
  }

  String? _assignmentLabel(Asset asset) {
    final a = _activeByAsset[asset.id];
    if (a == null) return null;
    final name = switch (a.assignableType) {
      AssignableType.user => _userNameById[a.assignableId] ?? a.assignableId,
      AssignableType.team => _teamNameById[a.assignableId] ?? a.assignableId,
      AssignableType.mission => _missionNameById[a.assignableId] ?? a.assignableId,
    };
    final kind = switch (a.assignableType) {
      AssignableType.user => 'User',
      AssignableType.team => 'Team',
      AssignableType.mission => 'Mission',
    };
    return '$kind: $name';
  }

  Future<void> _createAsset() async {
    final typeCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    var status = 'Available';
    const statusOptions = ['Available', 'Deployed', 'Out of Service', 'Maintenance'];
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Asset'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: typeCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Type', hintText: 'e.g. Vehicle, Rope Kit'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(labelText: 'Identifier', hintText: 'e.g. Engine 7'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setDialogState(() => status = v ?? status),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (created != true || typeCtrl.text.trim().isEmpty || idCtrl.text.trim().isEmpty) return;
    try {
      await AssetService.instance.createAsset(
        type: typeCtrl.text.trim(),
        identifier: idCtrl.text.trim(),
        status: status,
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create asset: $e')));
      }
    }
  }

  Future<void> _unassign(Asset asset) async {
    try {
      await AssetService.instance.unassignAsset(asset.id, unassignedBy: 'Command Console');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not unassign: $e')));
      }
    }
  }

  Future<void> _reassign(Asset asset) async {
    final result = await showModalBottomSheet<({AssignableType type, String id})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReassignSheet(
        userNameById: _userNameById,
        teamNameById: _teamNameById,
        missionNameById: _missionNameById,
      ),
    );
    if (result == null) return;
    try {
      switch (result.type) {
        case AssignableType.user:
          await AssetService.instance.assignAssetToUser(asset.id, result.id, assignedBy: 'Command Console');
        case AssignableType.team:
          await AssetService.instance.assignAssetToTeam(asset.id, result.id, assignedBy: 'Command Console');
        case AssignableType.mission:
          await AssetService.instance.assignAssetToMission(asset.id, result.id, assignedBy: 'Command Console');
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign: $e')));
      }
    }
  }

  Future<void> _deleteAsset(Asset asset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Asset?'),
        content: Text('Remove ${asset.identifier} (${asset.type}) permanently? '
            'This also removes its assignment history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AssetService.instance.deleteAsset(asset.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete asset: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final types = _assets.map((a) => a.type).toSet().toList()..sort();
    final statuses = _assets.map((a) => a.status).toSet().toList()..sort();

    final filtered = _assets.where((a) {
      if (_typeFilter != null && a.type != _typeFilter) return false;
      if (_statusFilter != null && a.status != _statusFilter) return false;
      if (query.isEmpty) return true;
      final assignLabel = _assignmentLabel(a)?.toLowerCase() ?? '';
      return a.identifier.toLowerCase().contains(query) ||
          a.type.toLowerCase().contains(query) ||
          assignLabel.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assets'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAsset,
        icon: const Icon(Icons.add),
        label: const Text('New Asset'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search by identifier, type, or assignee…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    hint: const Text('Type'),
                    value: _typeFilter,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All types')),
                      ...types.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                    ],
                    onChanged: (v) => setState(() => _typeFilter = v),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    hint: const Text('Status'),
                    value: _statusFilter,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All statuses')),
                      ...statuses.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                ]),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('No assets match.', style: TextStyle(color: Colors.grey[600])))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final asset = filtered[i];
                          final assignLabel = _assignmentLabel(asset);
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text('${asset.identifier} — ${asset.type}'),
                              subtitle: Text('${asset.status} • ${assignLabel ?? 'Unassigned'}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'reassign') _reassign(asset);
                                  if (v == 'unassign') _unassign(asset);
                                  if (v == 'delete') _deleteAsset(asset);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'reassign', child: Text('Assign / Reassign')),
                                  if (assignLabel != null)
                                    const PopupMenuItem(value: 'unassign', child: Text('Unassign')),
                                  const PopupMenuItem(
                                      value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

class _ReassignSheet extends StatefulWidget {
  final Map<String, String> userNameById;
  final Map<String, String> teamNameById;
  final Map<String, String> missionNameById;
  const _ReassignSheet({
    required this.userNameById,
    required this.teamNameById,
    required this.missionNameById,
  });

  @override
  State<_ReassignSheet> createState() => _ReassignSheetState();
}

class _ReassignSheetState extends State<_ReassignSheet> {
  AssignableType _type = AssignableType.user;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _pool => switch (_type) {
        AssignableType.user => widget.userNameById,
        AssignableType.team => widget.teamNameById,
        AssignableType.mission => widget.missionNameById,
      };

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final entries = _pool.entries.where((e) => query.isEmpty || e.value.toLowerCase().contains(query)).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign To', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<AssignableType>(
            segments: const [
              ButtonSegment(value: AssignableType.user, label: Text('User'), icon: Icon(Icons.person)),
              ButtonSegment(value: AssignableType.team, label: Text('Team'), icon: Icon(Icons.groups)),
              ButtonSegment(
                  value: AssignableType.mission, label: Text('Mission'), icon: Icon(Icons.local_fire_department)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
                hintText: 'Search…', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: entries.isEmpty
                ? Center(child: Text('None found.', style: TextStyle(color: Colors.grey[600])))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return ListTile(
                        title: Text(e.value),
                        onTap: () => Navigator.pop(context, (type: _type, id: e.key)),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
