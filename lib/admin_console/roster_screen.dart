import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../tac_map.dart' show TacUser;
import 'incident_service.dart';
import 'no_incident_placeholder.dart';

class RosterScreen extends StatefulWidget {
  final TacIncident? incident;
  const RosterScreen({super.key, required this.incident});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  List<IncidentMember> _members = [];
  List<TacUser> _online = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RosterScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.id != widget.incident?.id) _load();
  }

  Future<void> _load() async {
    final incident = widget.incident;
    if (incident == null) return;
    setState(() => _loading = true);
    final members = await IncidentService.instance.fetchMembers(incident.id);
    var online = <TacUser>[];
    final client = SupabaseService.client;
    if (client != null) {
      try {
        final rows = await client
            .from('tac_users')
            .select()
            .eq('mission_code', incident.missionCode) as List;
        online = rows.map((r) => TacUser.fromMap(r as Map<String, dynamic>)).toList();
      } catch (_) {}
    }
    if (mounted) setState(() { _members = members; _online = online; _loading = false; });
  }

  Future<void> _addOnlineUser(TacUser user) async {
    final incident = widget.incident;
    if (incident == null) return;
    await IncidentService.instance.addMember(incident.id, userId: user.id, callsign: user.callsign);
    _load();
  }

  Future<void> _removeMember(IncidentMember member) async {
    await IncidentService.instance.markMemberLeft(member.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incident == null) {
      return const NoIncidentPlaceholder(feature: 'Roster');
    }
    final memberUserIds = _members.where((m) => m.isActive).map((m) => m.userId).toSet();
    final unattached = _online.where((u) => !memberUserIds.contains(u.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('On this incident (${_members.where((m) => m.isActive).length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._members.where((m) => m.isActive).map((m) {
                  final isOnline = _online.any((u) => u.id == m.userId);
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.circle, size: 12,
                          color: isOnline ? Colors.green : Colors.grey),
                      title: Text(m.callsign.isEmpty ? m.userId : m.callsign),
                      subtitle: Text(isOnline ? 'Online' : 'Offline — not currently broadcasting'),
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
                      child: Text(
                        'No one has joined mission code ${widget.incident!.missionCode} yet.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
