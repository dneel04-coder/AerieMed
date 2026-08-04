import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../protocol_admin.dart' show ProtocolSyncService, DeploymentOrder, DeploymentOrderService;
import '../incident_service.dart';
import 'no_incident_placeholder.dart';

class DeploymentOrdersConsoleScreen extends StatefulWidget {
  final TacIncident? incident;
  const DeploymentOrdersConsoleScreen({super.key, required this.incident});

  @override
  State<DeploymentOrdersConsoleScreen> createState() => _DeploymentOrdersConsoleScreenState();
}

class _DeploymentOrdersConsoleScreenState extends State<DeploymentOrdersConsoleScreen> {
  List<DeploymentOrder> _orders = [];
  List<IncidentMember> _members = [];
  bool _loading = true;
  bool _dragging = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DeploymentOrdersConsoleScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.id != widget.incident?.id) _load();
  }

  Future<void> _load() async {
    final incident = widget.incident;
    if (incident == null) return;
    setState(() => _loading = true);
    final orders = await ProtocolSyncService.instance.allDeploymentOrders();
    final members = await IncidentService.instance.fetchMembers(incident.id);
    if (mounted) setState(() {
      _orders = orders;
      _members = members.where((m) => m.isActive).toList();
      _loading = false;
    });
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.single.bytes == null) return;
    await _showUploadDialog(result.files.single.bytes!, result.files.single.name);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      final bytes = await file.readAsBytes();
      await _showUploadDialog(bytes, file.name);
    }
  }

  Future<void> _showUploadDialog(Uint8List bytes, String fileName) async {
    final titleCtrl = TextEditingController(text: fileName);
    final notesCtrl = TextEditingController();
    final selected = <String>{}; // userIds; empty + everyone==true => broadcast
    var everyone = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Push "$fileName"'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 10),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 2),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Send to everyone'),
                  value: everyone,
                  onChanged: (v) => setDialogState(() => everyone = v),
                ),
                if (!everyone) ...[
                  const Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No one on this incident\'s roster yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  ..._members.map((m) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.callsign.isEmpty ? m.userId : m.callsign),
                        value: selected.contains(m.userId),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(m.userId);
                          } else {
                            selected.remove(m.userId);
                          }
                        }),
                      )),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (!everyone && selected.isEmpty) ? null : () => Navigator.pop(ctx, true),
              child: const Text('Push'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _uploading = true);
    try {
      await ProtocolSyncService.instance.uploadDeploymentOrder(
        title: titleCtrl.text.trim().isEmpty ? fileName : titleCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        bytes: bytes,
        fileName: fileName,
        uploadedBy: 'Command Console',
        targetUserIds: everyone ? null : selected.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(everyone ? 'Pushed to everyone' : 'Pushed to ${selected.length} recipient(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Push failed: $e')));
      }
    }
    if (mounted) setState(() => _uploading = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incident == null) {
      return const NoIncidentPlaceholder(feature: 'Deployment Orders');
    }
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _handleDrop(details);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Deployment Orders'),
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
              const Text('Drag & drop a file here to push it to field devices'),
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
                : _orders.isEmpty
                    ? Center(child: Text('No orders pushed yet.', style: TextStyle(color: Colors.grey[600])))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _orders.length,
                        itemBuilder: (_, i) {
                          final o = _orders[i];
                          final targeted = o.targetUserIds != null;
                          return Card(
                            child: ListTile(
                              leading: Icon(targeted ? Icons.person_pin_circle_outlined : Icons.public,
                                  color: targeted ? Colors.orange : Colors.blueGrey),
                              title: Text(o.title),
                              subtitle: Text(targeted
                                  ? 'Targeted — ${o.targetUserIds!.length} recipient(s) • ${o.uploadedBy}'
                                  : 'Everyone • ${o.uploadedBy}'),
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
