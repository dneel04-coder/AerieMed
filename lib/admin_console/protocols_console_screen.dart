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
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.bytes == null) return;
    await _showUploadDialog(result.files.single.bytes!, result.files.single.name);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      if (!file.name.toLowerCase().endsWith('.pdf')) continue;
      final bytes = await file.readAsBytes();
      await _showUploadDialog(bytes, file.name);
    }
  }

  Future<void> _showUploadDialog(Uint8List bytes, String fileName) async {
    final nameCtrl = TextEditingController(text: fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
    final notesCtrl = TextEditingController();
    var scope = _ProtocolScope.everyone;
    Team? selectedTeam;
    final selectedUsers = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Push "$fileName"'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Protocol Name')),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
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
      await ProtocolSyncService.instance.uploadProtocol(
        name: nameCtrl.text.trim().isEmpty ? fileName : nameCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        bytes: bytes,
        uploadedBy: 'Command Console',
        targetUserIds: scope == _ProtocolScope.users ? selectedUsers.toList() : null,
        targetTeamId: scope == _ProtocolScope.team ? selectedTeam?.id : null,
      );
      if (mounted) {
        final label = switch (scope) {
          _ProtocolScope.everyone => 'Pushed to everyone',
          _ProtocolScope.team => 'Pushed to team "${selectedTeam?.name}"',
          _ProtocolScope.users => 'Pushed to ${selectedUsers.length} recipient(s)',
        };
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
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        ),
        body: Column(children: [
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
              const Text('Drag & drop a protocol PDF here to push it to field devices'),
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
                : _protocols.isEmpty
                    ? Center(child: Text('No protocols pushed yet.', style: TextStyle(color: Colors.grey[600])))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _protocols.length,
                        itemBuilder: (_, i) {
                          final p = _protocols[i];
                          return Card(
                            child: ListTile(
                              leading: Icon(_scopeIcon(p),
                                  color: p.targetTeamId != null || p.targetUserIds != null ? Colors.orange : Colors.blueGrey),
                              title: Text(p.name),
                              subtitle: Text('${_scopeLabel(p)} • v${p.version} • ${p.updatedBy}'),
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
