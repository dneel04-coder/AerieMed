import 'package:flutter/material.dart';
import 'admin_shell.dart';
import '../incident_service.dart';

class IncidentScreen extends StatefulWidget {
  final ActiveIncidentController controller;
  const IncidentScreen({super.key, required this.controller});

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen> {
  List<TacIncident> _incidents = [];
  bool _loading = true;
  final Set<String> _expanded = {};
  final Map<String, List<IncidentMember>> _membersByIncident = {};
  final Set<String> _loadingMembers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final incidents = await IncidentService.instance.fetchIncidents();
    if (mounted) setState(() { _incidents = incidents; _loading = false; });
  }

  Future<void> _createIncident() async {
    final nameCtrl = TextEditingController();
    final code = IncidentService.instance.generateMissionCode();
    final codeCtrl = TextEditingController(text: code);
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Incident'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Incident name', hintText: 'e.g. Ridge Fire — Div A'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: codeCtrl,
            decoration: const InputDecoration(
              labelText: 'Mission code',
              helperText: 'Field users type this into "Join Mission" on their app',
            ),
            textCapitalization: TextCapitalization.characters,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || !mounted) return;
    try {
      final incident = await IncidentService.instance.createIncident(
        name: nameCtrl.text.trim(),
        missionCode: codeCtrl.text.trim().toUpperCase(),
      );
      if (incident != null) {
        widget.controller.select(incident);
        _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create incident — check Settings/connection.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create incident: $e')),
        );
      }
    }
  }

  Future<void> _toggleExpanded(TacIncident incident) async {
    if (_expanded.contains(incident.id)) {
      setState(() => _expanded.remove(incident.id));
      return;
    }
    setState(() => _expanded.add(incident.id));
    if (_membersByIncident.containsKey(incident.id)) return;
    setState(() => _loadingMembers.add(incident.id));
    final members = await IncidentService.instance.fetchMembers(incident.id);
    if (mounted) {
      setState(() {
        _membersByIncident[incident.id] = members;
        _loadingMembers.remove(incident.id);
      });
    }
  }

  Future<void> _closeIncident(TacIncident incident) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Incident?'),
        content: Text(
            'This marks "${incident.name.isEmpty ? incident.missionCode : incident.name}" as closed. '
            'Field devices already on mission code ${incident.missionCode} are not notified — this is admin-side bookkeeping only.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close Incident')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await IncidentService.instance.closeIncident(incident.id);
      if (widget.controller.incident?.id == incident.id) widget.controller.select(null);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not close incident: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidents'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createIncident,
        icon: const Icon(Icons.add),
        label: const Text('New Incident'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _incidents.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_fire_department_outlined, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    const Text('No incidents yet'),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _incidents.length,
                  itemBuilder: (_, i) {
                    final incident = _incidents[i];
                    final active = widget.controller.incident?.id == incident.id;
                    final isExpanded = _expanded.contains(incident.id);
                    final members = _membersByIncident[incident.id]
                            ?.where((m) => m.isActive)
                            .toList() ??
                        const <IncidentMember>[];
                    return Card(
                      color: active ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: Column(children: [
                        ListTile(
                          leading: Icon(incident.isOpen ? Icons.local_fire_department : Icons.check_circle_outline,
                              color: incident.isOpen ? Colors.deepOrange : Colors.grey),
                          title: Text(incident.name.isEmpty ? incident.missionCode : incident.name),
                          subtitle: Text('Code: ${incident.missionCode} • Opened ${_fmt(incident.openedAt)}'
                              '${incident.isOpen ? '' : ' • Closed ${_fmt(incident.closedAt!)}'}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (incident.isOpen)
                              IconButton(
                                icon: const Icon(Icons.stop_circle_outlined),
                                tooltip: 'Close incident',
                                onPressed: () => _closeIncident(incident),
                              ),
                            IconButton(
                              icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                              tooltip: isExpanded ? 'Hide assigned' : 'Show assigned',
                              onPressed: () => _toggleExpanded(incident),
                            ),
                          ]),
                          onTap: () => widget.controller.select(incident),
                        ),
                        if (isExpanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _loadingMembers.contains(incident.id)
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: SizedBox(
                                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : members.isEmpty
                                      ? Text('No one assigned yet.',
                                          style: TextStyle(color: Colors.grey[600], fontSize: 13))
                                      : Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: members
                                              .map((m) => Chip(
                                                    avatar: Icon(
                                                        m.isPending ? Icons.hourglass_top : Icons.check_circle,
                                                        size: 16),
                                                    label: Text(m.callsign.isEmpty ? m.userId : m.callsign),
                                                    visualDensity: VisualDensity.compact,
                                                  ))
                                              .toList(),
                                        ),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
