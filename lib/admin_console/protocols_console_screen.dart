import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../protocol_admin.dart' show ProtocolSyncService, ProtocolEntry, SupabaseService;
import '../asset_service.dart' show AssetService, Team;

/// A user_profiles row, just enough to pick recipients -- mirrors
/// roster_screen.dart's unfiltered directory fetch, kept local here since
/// that file's _DirectoryUser is private to it.
class _RosterUser {
  final String userId;
  final String display;
  final String? teamId;
  const _RosterUser({required this.userId, required this.display, this.teamId});
}

enum _ProtocolScope { everyone, team, users }

class _PickedFile {
  final Uint8List bytes;
  final String name;
  const _PickedFile(this.bytes, this.name);
}

/// Lets a medical director push a protocol PDF to everyone, a specific
/// Team, or specific individual users -- not incident-scoped, since
/// protocols are a standing library independent of any active incident
/// (unlike Deployment Orders, which this screen's drag-and-drop UX mirrors).
class ProtocolsConsoleScreen extends StatefulWidget {
  const ProtocolsConsoleScreen({super.key});

  @override
  State<ProtocolsConsoleScreen> createState() => _ProtocolsConsoleScreenState();
}

class _ProtocolsConsoleScreenState extends State<ProtocolsConsoleScreen> {
  List<ProtocolEntry> _protocols = [];
  List<_RosterUser> _roster = [];
  List<Team> _teams = [];
  bool _loading = true;
  bool _dragging = false;
  bool _uploading = false;
  String _categoryFilter = 'medical';

  List<ProtocolEntry> get _filtered => _protocols.where((p) => p.category == _categoryFilter).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final protocols = await ProtocolSyncService.instance.allProtocols();
    final teams = await AssetService.instance.fetchTeams();
    var roster = <_RosterUser>[];
    final client = SupabaseService.client;
    if (client != null) {
      try {
        final rows = await client.from('user_profiles').select() as List;
        roster = rows
            .map((r) {
              final m = r as Map<String, dynamic>;
              final callsign = m['callsign'] as String? ?? '';
              final name = m['name'] as String? ?? '';
              return _RosterUser(
                userId: m['user_id'] as String? ?? '',
                display: callsign.isNotEmpty ? callsign : (name.isNotEmpty ? name : (m['user_id'] as String? ?? '')),
                teamId: m['team_id'] as String?,
              );
            })
            .where((u) => u.userId.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _protocols = protocols;
        _teams = teams;
        _roster = roster;
        _loading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
        withData: true, type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (result == null) return;
    final files = result.files.where((f) => f.bytes != null).map((f) => _PickedFile(f.bytes!, f.name)).toList();
    if (files.isEmpty) return;
    await _showUploadDialog(files);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    final files = <_PickedFile>[];
    for (final file in details.files) {
      if (!file.name.toLowerCase().endsWith('.pdf')) continue;
      files.add(_PickedFile(await file.readAsBytes(), file.name));
    }
    if (files.isEmpty) return;
    await _showUploadDialog(files);
  }

  Future<void> _showUploadDialog(List<_PickedFile> files) async {
    final nameCtrls = [
      for (final f in files) TextEditingController(text: f.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''))
    ];
    final notesCtrl = TextEditingController();
    var category = _categoryFilter;
    var scope = _ProtocolScope.everyone;
    Team? selectedTeam;
    final selectedUsers = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(files.length == 1 ? 'Push "${files.first.name}"' : 'Push ${files.length} files'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < files.length; i++) ...[
                  TextField(
                    controller: nameCtrls[i],
                    decoration: InputDecoration(
                      labelText: files.length == 1 ? 'Protocol Name' : 'Protocol Name (${files[i].name})',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
                const SizedBox(height: 16),
                const Text('Destination', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'medical', label: Text('Protocols'), icon: Icon(Icons.menu_book_outlined)),
                    ButtonSegment(value: 'team', label: Text('Team Protocols'), icon: Icon(Icons.description_outlined)),
                  ],
                  selected: {category},
                  onSelectionChanged: (s) => setDialogState(() => category = s.first),
                ),
                const SizedBox(height: 16),
                const Text('Send to', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<_ProtocolScope>(
                  segments: const [
                    ButtonSegment(value: _ProtocolScope.everyone, label: Text('Everyone'), icon: Icon(Icons.public)),
                    ButtonSegment(value: _ProtocolScope.team, label: Text('Team'), icon: Icon(Icons.groups)),
                    ButtonSegment(value: _ProtocolScope.users, label: Text('Specific Users'), icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) => setDialogState(() => scope = s.first),
                ),
                if (scope == _ProtocolScope.team) ...[
                  const SizedBox(height: 12),
                  if (_teams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No teams yet — create one from Roster > Assign to Team.', style: TextStyle(color: Colors.grey[600])),
                    )
                  else
                    DropdownButtonFormField<Team>(
                      initialValue: selectedTeam,
                      decoration: const InputDecoration(labelText: 'Team', border: OutlineInputBorder(), isDense: true),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                      onChanged: (v) => setDialogState(() => selectedTeam = v),
                    ),
                ],
                if (scope == _ProtocolScope.users) ...[
                  const SizedBox(height: 12),
                  const Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_roster.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No users found yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: _roster.map((u) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(u.display),
                            value: selectedUsers.contains(u.userId),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedUsers.add(u.userId);
                              } else {
                                selectedUsers.remove(u.userId);
                              }
                            }),
                          )).toList(),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (scope == _ProtocolScope.team && selectedTeam == null) ||
                      (scope == _ProtocolScope.users && selectedUsers.isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Push'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    try {
      for (var i = 0; i < files.length; i++) {
        await ProtocolSyncService.instance.uploadProtocol(
          name: nameCtrls[i].text.trim().isEmpty ? files[i].name : nameCtrls[i].text.trim(),
          notes: notesCtrl.text.trim(),
          bytes: files[i].bytes,
          uploadedBy: 'Command Console',
          targetUserIds: scope == _ProtocolScope.users ? selectedUsers.toList() : null,
          targetTeamId: scope == _ProtocolScope.team ? selectedTeam?.id : null,
          category: category,
        );
      }
      if (mounted) {
        final dest = category == 'medical' ? 'Protocols' : 'Team Protocols';
        final target = switch (scope) {
          _ProtocolScope.everyone => 'everyone',
          _ProtocolScope.team => 'team "${selectedTeam?.name}"',
          _ProtocolScope.users => '${selectedUsers.length} recipient(s)',
        };
        final label = files.length == 1
            ? 'Pushed to $dest ($target)'
            : 'Pushed ${files.length} protocols to $dest ($target)';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Push failed: $e')));
      }
    }
    if (mounted) setState(() => _uploading = false);
    _load();
  }

  String _scopeLabel(ProtocolEntry p) {
    if (p.targetTeamId != null) {
      final team = _teams.where((t) => t.id == p.targetTeamId).firstOrNull;
      return 'Team "${team?.name ?? 'Unknown'}"';
    }
    if (p.targetUserIds != null) {
      return '${p.targetUserIds!.length} specific user(s)';
    }
    return 'Everyone';
  }

  IconData _scopeIcon(ProtocolEntry p) {
    if (p.targetTeamId != null) return Icons.groups;
    if (p.targetUserIds != null) return Icons.person_pin_circle_outlined;
    return Icons.public;
  }

  Future<void> _confirmDelete(ProtocolEntry p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete protocol?'),
        content: Text(
            '"${p.name}" will be removed from the library. Any device that already downloaded it will delete its local copy the next time it syncs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ProtocolSyncService.instance.deleteProtocol(p);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "${p.name}"')));
    }
    _load();
  }

  Future<void> _confirmDeleteAll() async {
    final destLabel = _categoryFilter == 'medical' ? 'Protocols' : 'Team Protocols';
    final count = _filtered.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete all $destLabel?'),
        content: Text(
            'This permanently removes all $count protocol(s) under "$destLabel" from the library. Any device that already downloaded one will delete its local copy the next time it syncs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _uploading = true);
    await ProtocolSyncService.instance.deleteAllProtocols(category: _categoryFilter);
    if (mounted) {
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('All $destLabel deleted')));
    }
    _load();
  }

  Future<void> _confirmEditRecipients(ProtocolEntry p) async {
    var scope = p.targetTeamId != null
        ? _ProtocolScope.team
        : p.targetUserIds != null
            ? _ProtocolScope.users
            : _ProtocolScope.everyone;
    Team? selectedTeam = p.targetTeamId == null ? null : _teams.where((t) => t.id == p.targetTeamId).firstOrNull;
    final selectedUsers = <String>{...?p.targetUserIds};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Recipients — ${p.name}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<_ProtocolScope>(
                  segments: const [
                    ButtonSegment(value: _ProtocolScope.everyone, label: Text('Everyone'), icon: Icon(Icons.public)),
                    ButtonSegment(value: _ProtocolScope.team, label: Text('Team'), icon: Icon(Icons.groups)),
                    ButtonSegment(value: _ProtocolScope.users, label: Text('Specific Users'), icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) => setDialogState(() => scope = s.first),
                ),
                if (scope == _ProtocolScope.team) ...[
                  const SizedBox(height: 12),
                  if (_teams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No teams yet — create one from Roster > Assign to Team.', style: TextStyle(color: Colors.grey[600])),
                    )
                  else
                    DropdownButtonFormField<Team>(
                      initialValue: selectedTeam,
                      decoration: const InputDecoration(labelText: 'Team', border: OutlineInputBorder(), isDense: true),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                      onChanged: (v) => setDialogState(() => selectedTeam = v),
                    ),
                ],
                if (scope == _ProtocolScope.users) ...[
                  const SizedBox(height: 12),
                  const Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_roster.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No users found yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: _roster.map((u) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(u.display),
                            value: selectedUsers.contains(u.userId),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedUsers.add(u.userId);
                              } else {
                                selectedUsers.remove(u.userId);
                              }
                            }),
                          )).toList(),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (scope == _ProtocolScope.team && selectedTeam == null) ||
                      (scope == _ProtocolScope.users && selectedUsers.isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ProtocolSyncService.instance.updateProtocolTargeting(
        p.id,
        targetUserIds: scope == _ProtocolScope.users ? selectedUsers.toList() : null,
        targetTeamId: scope == _ProtocolScope.team ? selectedTeam?.id : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated recipients for "${p.name}"')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _handleDrop(details);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Protocols'),
          actions: [
            if (_filtered.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Delete All',
                onPressed: _uploading ? null : _confirmDeleteAll,
              ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'medical', label: Text('Protocols'), icon: Icon(Icons.menu_book_outlined)),
                ButtonSegment(value: 'team', label: Text('Team Protocols'), icon: Icon(Icons.description_outlined)),
              ],
              selected: {_categoryFilter},
              onSelectionChanged: (s) => setState(() => _categoryFilter = s.first),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(
                  color: _dragging ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                  width: 2, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(12),
              color: _dragging ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
            ),
            child: Column(children: [
              Icon(Icons.upload_file, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              const Text('Drag & drop one or more protocol PDFs here to push them to field devices'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickAndUpload,
                icon: const Icon(Icons.folder_open),
                label: const Text('Browse files'),
              ),
              if (_uploading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                            _categoryFilter == 'medical' ? 'No protocols pushed yet.' : 'No team protocols pushed yet.',
                            style: TextStyle(color: Colors.grey[600])))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final p = _filtered[i];
                          return Card(
                            child: ListTile(
                              leading: Icon(_scopeIcon(p),
                                  color: p.targetTeamId != null || p.targetUserIds != null ? Colors.orange : Colors.blueGrey),
                              title: Text(p.name),
                              subtitle: Text('${_scopeLabel(p)} • v${p.version} • ${p.updatedBy}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Edit Recipients',
                                    onPressed: () => _confirmEditRecipients(p),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Delete',
                                    onPressed: () => _confirmDelete(p),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
