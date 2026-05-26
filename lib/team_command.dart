import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kCerts = ['WFA', 'WFR', 'WEMT', 'EMT-B', 'AEMT', 'Paramedic', 'RN', 'MD/DO', 'Other'];
const _kMemberStatuses = ['Available', 'On Task', 'Rest', 'Off-Op'];
const _kIncidentTypes = ['Search & Rescue', 'Medical', 'Wildfire', 'Evacuation', 'Technical Rescue', 'Training', 'Other'];
const _kIncidentStatuses = ['Active', 'Standby', 'Demobilized'];
const _kPriorities = ['Critical', 'High', 'Normal', 'Low'];
const _kTaskStatuses = ['Pending', 'In Progress', 'Complete', 'Blocked'];
const _kDefaultRoles = [
  'Incident Commander (IC)', 'Medical Officer', 'Operations Section Chief',
  'Logistics', 'Transport / Evacuation', 'Safety Officer',
  'Communications (COMMS)', 'Triage Officer', 'Treatment Officer', 'Base Camp',
];

// ── Colour helpers ────────────────────────────────────────────────────────────

Color _certColor(String c) {
  switch (c) {
    case 'WFA': return Colors.lightBlue;
    case 'WFR': return Colors.blue;
    case 'WEMT': return Colors.purple;
    case 'EMT-B': return Colors.green;
    case 'AEMT': return Colors.teal;
    case 'Paramedic': return Colors.red;
    case 'RN': return Colors.orange;
    case 'MD/DO': return Colors.deepPurple;
    default: return Colors.grey;
  }
}

Color _priorityColor(String p) {
  switch (p) {
    case 'Critical': return Colors.red;
    case 'High': return Colors.orange;
    case 'Normal': return Colors.blue;
    case 'Low': return Colors.grey;
    default: return Colors.blue;
  }
}

Color _taskStatusColor(String s) {
  switch (s) {
    case 'Pending': return Colors.grey;
    case 'In Progress': return Colors.blue;
    case 'Complete': return Colors.green;
    case 'Blocked': return Colors.red;
    default: return Colors.grey;
  }
}

Color _memberStatusColor(String s) {
  switch (s) {
    case 'Available': return Colors.green;
    case 'On Task': return Colors.blue;
    case 'Rest': return Colors.orange;
    case 'Off-Op': return Colors.grey;
    default: return Colors.grey;
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class IcRole {
  String title;
  String assignedTo;
  IcRole({required this.title, this.assignedTo = ''});

  Map<String, dynamic> toJson() => {'title': title, 'assignedTo': assignedTo};
  factory IcRole.fromJson(Map<String, dynamic> j) =>
      IcRole(title: j['title'] as String? ?? '', assignedTo: j['assignedTo'] as String? ?? '');
}

class Incident {
  final String id;
  final DateTime startedAt;
  String name, type, location, status, notes;
  List<IcRole> roles;

  Incident({
    required this.id,
    required this.startedAt,
    this.name = '',
    this.type = '',
    this.location = '',
    this.status = 'Active',
    this.notes = '',
    List<IcRole>? roles,
  }) : roles = roles ?? _defaultRoles();

  factory Incident.fresh() => Incident(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startedAt: DateTime.now(),
      );

  static List<IcRole> _defaultRoles() => [
        IcRole(title: 'Incident Commander (IC)'),
        IcRole(title: 'Medical Officer'),
        IcRole(title: 'Transport / Evacuation'),
        IcRole(title: 'Communications (COMMS)'),
        IcRole(title: 'Safety Officer'),
        IcRole(title: 'Logistics'),
      ];

  String get displayTitle => name.isEmpty ? 'Unnamed Incident' : name;

  static String _z(int n) => n.toString().padLeft(2, '0');
  String get timeDisplay {
    final t = startedAt.toLocal();
    return '${t.year}-${_z(t.month)}-${_z(t.day)} ${_z(t.hour)}${_z(t.minute)}Z';
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'startedAt': startedAt.toIso8601String(),
        'name': name, 'type': type, 'location': location,
        'status': status, 'notes': notes,
        'roles': roles.map((r) => r.toJson()).toList(),
      };

  factory Incident.fromJson(Map<String, dynamic> j) => Incident(
        id: j['id'] as String? ?? '',
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        location: j['location'] as String? ?? '',
        status: j['status'] as String? ?? 'Active',
        notes: j['notes'] as String? ?? '',
        roles: (j['roles'] as List? ?? [])
            .map((e) => IcRole.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TeamMember {
  final String id;
  String name, callsign, certification, certExpiry, contact, status, notes;
  List<String> additionalCerts;

  TeamMember({
    required this.id,
    this.name = '',
    this.callsign = '',
    this.certification = 'WFR',
    this.certExpiry = '',
    this.contact = '',
    this.status = 'Available',
    this.notes = '',
    List<String>? additionalCerts,
  }) : additionalCerts = additionalCerts ?? [];

  factory TeamMember.fresh() =>
      TeamMember(id: DateTime.now().millisecondsSinceEpoch.toString());

  String get displayName => name.isEmpty ? (callsign.isEmpty ? 'Unnamed' : callsign) : name;

  bool get isCertExpired {
    if (certExpiry.isEmpty) return false;
    final d = DateTime.tryParse(certExpiry);
    return d != null && d.isBefore(DateTime.now());
  }

  bool get isCertExpiringSoon {
    if (certExpiry.isEmpty) return false;
    final d = DateTime.tryParse(certExpiry);
    return d != null && d.isBefore(DateTime.now().add(const Duration(days: 90)));
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'callsign': callsign,
        'certification': certification, 'certExpiry': certExpiry,
        'contact': contact, 'status': status, 'notes': notes,
        'additionalCerts': additionalCerts,
      };

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        callsign: j['callsign'] as String? ?? '',
        certification: j['certification'] as String? ?? 'WFR',
        certExpiry: j['certExpiry'] as String? ?? '',
        contact: j['contact'] as String? ?? '',
        status: j['status'] as String? ?? 'Available',
        notes: j['notes'] as String? ?? '',
        additionalCerts: (j['additionalCerts'] as List? ?? []).cast<String>(),
      );
}

class OpTask {
  final String id;
  final DateTime createdAt;
  String title, description, assignedTo, priority, status, notes;

  OpTask({
    required this.id,
    required this.createdAt,
    this.title = '',
    this.description = '',
    this.assignedTo = '',
    this.priority = 'Normal',
    this.status = 'Pending',
    this.notes = '',
  });

  factory OpTask.fresh() => OpTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'createdAt': createdAt.toIso8601String(),
        'title': title, 'description': description,
        'assignedTo': assignedTo, 'priority': priority,
        'status': status, 'notes': notes,
      };

  factory OpTask.fromJson(Map<String, dynamic> j) => OpTask(
        id: j['id'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        assignedTo: j['assignedTo'] as String? ?? '',
        priority: j['priority'] as String? ?? 'Normal',
        status: j['status'] as String? ?? 'Pending',
        notes: j['notes'] as String? ?? '',
      );
}

class ShiftHandoff {
  final String id;
  final DateTime createdAt;
  String outgoingLead, incomingLead, incidentStatus, patientStatus,
      teamStatus, pendingTasks, criticalInfo, resourceStatus, notes;

  ShiftHandoff({
    required this.id,
    required this.createdAt,
    this.outgoingLead = '',
    this.incomingLead = '',
    this.incidentStatus = '',
    this.patientStatus = '',
    this.teamStatus = '',
    this.pendingTasks = '',
    this.criticalInfo = '',
    this.resourceStatus = '',
    this.notes = '',
  });

  factory ShiftHandoff.fresh() => ShiftHandoff(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
      );

  static String _z(int n) => n.toString().padLeft(2, '0');
  String get timeDisplay {
    final t = createdAt.toLocal();
    return '${t.year}-${_z(t.month)}-${_z(t.day)} ${_z(t.hour)}${_z(t.minute)}Z';
  }

  String get formattedText {
    final lines = [
      '══════════════════════════════════════',
      '   SHIFT HANDOFF REPORT',
      '══════════════════════════════════════',
      'DATE / TIME : $timeDisplay',
      'OUTGOING    : ${outgoingLead.isEmpty ? '—' : outgoingLead}',
      'INCOMING    : ${incomingLead.isEmpty ? '—' : incomingLead}',
      '──────────────────────────────────────',
      '[1] INCIDENT STATUS',
      incidentStatus.isEmpty ? '(not documented)' : incidentStatus,
      '──────────────────────────────────────',
      '[2] PATIENT STATUS',
      patientStatus.isEmpty ? '(not documented)' : patientStatus,
      '──────────────────────────────────────',
      '[3] TEAM / PERSONNEL STATUS',
      teamStatus.isEmpty ? '(not documented)' : teamStatus,
      '──────────────────────────────────────',
      '[4] OUTSTANDING TASKS',
      pendingTasks.isEmpty ? '(none)' : pendingTasks,
      '──────────────────────────────────────',
      '[5] CRITICAL INFORMATION',
      criticalInfo.isEmpty ? '(none)' : criticalInfo,
      '──────────────────────────────────────',
      '[6] RESOURCES / LOGISTICS',
      resourceStatus.isEmpty ? '(not documented)' : resourceStatus,
      if (notes.isNotEmpty) ...[
        '──────────────────────────────────────',
        'NOTES',
        notes,
      ],
      '══════════════════════════════════════',
    ];
    return lines.join('\n');
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'createdAt': createdAt.toIso8601String(),
        'outgoingLead': outgoingLead, 'incomingLead': incomingLead,
        'incidentStatus': incidentStatus, 'patientStatus': patientStatus,
        'teamStatus': teamStatus, 'pendingTasks': pendingTasks,
        'criticalInfo': criticalInfo, 'resourceStatus': resourceStatus,
        'notes': notes,
      };

  factory ShiftHandoff.fromJson(Map<String, dynamic> j) => ShiftHandoff(
        id: j['id'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        outgoingLead: j['outgoingLead'] as String? ?? '',
        incomingLead: j['incomingLead'] as String? ?? '',
        incidentStatus: j['incidentStatus'] as String? ?? '',
        patientStatus: j['patientStatus'] as String? ?? '',
        teamStatus: j['teamStatus'] as String? ?? '',
        pendingTasks: j['pendingTasks'] as String? ?? '',
        criticalInfo: j['criticalInfo'] as String? ?? '',
        resourceStatus: j['resourceStatus'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
      );
}

// ── Storage ───────────────────────────────────────────────────────────────────

class IncidentStorage {
  static const _k = 'tc_incidents_v1';
  static Future<List<Incident>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? []).map((e) {
      try { return Incident.fromJson(jsonDecode(e) as Map<String, dynamic>); } catch (_) { return null; }
    }).whereType<Incident>().toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }
  static Future<void> save(Incident inc) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == inc.id);
    list.insert(0, inc);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

class RosterStorage {
  static const _k = 'tc_roster_v1';
  static Future<List<TeamMember>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? []).map((e) {
      try { return TeamMember.fromJson(jsonDecode(e) as Map<String, dynamic>); } catch (_) { return null; }
    }).whereType<TeamMember>().toList();
  }
  static Future<void> save(TeamMember m) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == m.id);
    list.add(m);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

class TaskStorage {
  static const _k = 'tc_tasks_v1';
  static Future<List<OpTask>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? []).map((e) {
      try { return OpTask.fromJson(jsonDecode(e) as Map<String, dynamic>); } catch (_) { return null; }
    }).whereType<OpTask>().toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  static Future<void> save(OpTask t) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == t.id);
    list.insert(0, t);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

class HandoffStorage {
  static const _k = 'tc_handoffs_v1';
  static Future<List<ShiftHandoff>> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k) ?? []).map((e) {
      try { return ShiftHandoff.fromJson(jsonDecode(e) as Map<String, dynamic>); } catch (_) { return null; }
    }).whereType<ShiftHandoff>().toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  static Future<void> save(ShiftHandoff h) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == h.id);
    list.insert(0, h);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
  static Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((x) => x.id == id);
    await p.setStringList(_k, list.map((x) => jsonEncode(x.toJson())).toList());
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class TeamCommandScreen extends StatelessWidget {
  const TeamCommandScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Command'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.account_tree_outlined, size: 20), text: 'Incident'),
            Tab(icon: Icon(Icons.people_outlined, size: 20), text: 'Roster'),
            Tab(icon: Icon(Icons.task_alt, size: 20), text: 'Tasks'),
            Tab(icon: Icon(Icons.handshake_outlined, size: 20), text: 'Handoff'),
          ]),
        ),
        body: const TabBarView(children: [
          _IncidentTab(),
          _RosterTab(),
          _TasksTab(),
          _HandoffTab(),
        ]),
      ),
    );
  }
}

// ── Incident Tab ──────────────────────────────────────────────────────────────

class _IncidentTab extends StatefulWidget {
  const _IncidentTab();
  @override
  State<_IncidentTab> createState() => _IncidentTabState();
}

class _IncidentTabState extends State<_IncidentTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Incident> _incidents = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await IncidentStorage.load();
    if (mounted) setState(() { _incidents = d; _loading = false; });
  }

  Incident? get _active =>
      _incidents.where((i) => i.status == 'Active').firstOrNull;

  Future<void> _openForm([Incident? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _IncidentFormSheet(existing: existing),
    );
    if (result == true) _load();
  }

  Future<void> _assignRole(Incident inc, IcRole role) async {
    final members = await RosterStorage.load();
    if (!mounted) return;
    final ctrl = TextEditingController(text: role.assignedTo);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(role.title, style: const TextStyle(fontSize: 15)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (members.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: members.any((m) => m.displayName == role.assignedTo) ? role.assignedTo : null,
              decoration: const InputDecoration(labelText: 'From roster', border: OutlineInputBorder(), isDense: true),
              items: members.map((m) => DropdownMenuItem(
                value: m.displayName,
                child: Row(children: [
                  _CertBadge(m.certification),
                  const SizedBox(width: 6),
                  Text(m.displayName),
                  if (m.callsign.isNotEmpty) Text(' (${m.callsign})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              )).toList(),
              onChanged: (v) { if (v != null) ctrl.text = v; },
            ),
          if (members.isNotEmpty) const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Or type name', border: OutlineInputBorder(), isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Assign')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    role.assignedTo = result;
    await IncidentStorage.save(inc);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final active = _active;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          children: [
            // Active incident card
            if (active == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    const Text('No active incident', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Start New Incident'),
                      onPressed: () => _openForm(),
                    ),
                  ]),
                ),
              )
            else ...[
              _activeCard(active),
              const SizedBox(height: 12),
              _icStructureCard(active),
            ],

            // Archived incidents
            if (_incidents.where((i) => i.status != 'Active').isNotEmpty) ...[
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('ARCHIVED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              ),
              const SizedBox(height: 4),
              ..._incidents.where((i) => i.status != 'Active').map((inc) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey.withValues(alpha: 0.15),
                        child: const Icon(Icons.folder_outlined, color: Colors.grey, size: 20),
                      ),
                      title: Text(inc.displayTitle),
                      subtitle: Text('${inc.status}  •  ${inc.timeDisplay}', style: const TextStyle(fontSize: 11)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(inc)),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
                          await IncidentStorage.delete(inc.id);
                          _load();
                        }),
                      ]),
                    ),
                  )),
            ],
          ],
        ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'incident_fab',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('New Incident'),
          ),
        ),
      ],
    );
  }

  Widget _activeCard(Incident inc) {
    final statusColor = inc.status == 'Active' ? Colors.green : Colors.orange;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(4)),
              child: Text(inc.status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(inc.displayTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(inc)),
          ]),
          if (inc.type.isNotEmpty) ...[const SizedBox(height: 2), Text(inc.type, style: const TextStyle(color: Colors.grey, fontSize: 12))],
          if (inc.location.isNotEmpty) Row(children: [
            const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(child: Text(inc.location, style: const TextStyle(fontSize: 12))),
          ]),
          const SizedBox(height: 4),
          Text('Started: ${inc.timeDisplay}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (inc.notes.isNotEmpty) ...[
            const Divider(height: 12),
            Text(inc.notes, style: const TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  Widget _icStructureCard(Incident inc) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
            child: Row(children: [
              const Icon(Icons.account_tree, size: 16, color: Colors.indigo),
              const SizedBox(width: 6),
              const Expanded(child: Text('IC STRUCTURE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo, letterSpacing: 0.6))),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Role', style: TextStyle(fontSize: 12)),
                onPressed: () => _addCustomRole(inc),
              ),
            ]),
          ),
          const Divider(height: 1),
          ...inc.roles.asMap().entries.map((e) {
            final role = e.value;
            return ListTile(
              dense: true,
              title: Text(role.title, style: const TextStyle(fontSize: 13)),
              trailing: GestureDetector(
                onTap: () => _assignRole(inc, role),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: role.assignedTo.isEmpty
                        ? Colors.grey.withValues(alpha: 0.12)
                        : Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      role.assignedTo.isEmpty ? 'Unassigned' : role.assignedTo,
                      style: TextStyle(
                        fontSize: 12,
                        color: role.assignedTo.isEmpty ? Colors.grey : Colors.indigo,
                        fontWeight: role.assignedTo.isEmpty ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 12, color: Colors.grey),
                  ]),
                ),
              ),
              onLongPress: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Remove Role?'),
                    content: Text('Remove "${role.title}" from the IC structure?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) {
                  inc.roles.removeAt(e.key);
                  await IncidentStorage.save(inc);
                  _load();
                }
              },
            );
          }),
        ],
      ),
    );
  }

  Future<void> _addCustomRole(Incident inc) async {
    String? selected;
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
        title: const Text('Add Role'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Standard role', border: OutlineInputBorder(), isDense: true),
            items: _kDefaultRoles.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { setSt(() => selected = v); if (v != null) ctrl.text = v; },
          ),
          const SizedBox(height: 8),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Custom role title', border: OutlineInputBorder(), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? selected : ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      )),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    inc.roles.add(IcRole(title: result));
    await IncidentStorage.save(inc);
    _load();
  }
}

// ── Incident Form Sheet ───────────────────────────────────────────────────────

class _IncidentFormSheet extends StatefulWidget {
  final Incident? existing;
  const _IncidentFormSheet({this.existing});
  @override
  State<_IncidentFormSheet> createState() => _IncidentFormSheetState();
}

class _IncidentFormSheetState extends State<_IncidentFormSheet> {
  late final TextEditingController _name, _location, _notes;
  String _type = '', _status = 'Active';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _type = e?.type ?? '';
    _status = e?.status ?? 'Active';
  }

  @override
  void dispose() { _name.dispose(); _location.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    final inc = widget.existing ?? Incident.fresh();
    inc.name = _name.text.trim();
    inc.type = _type;
    inc.location = _location.text.trim();
    inc.status = _status;
    inc.notes = _notes.text.trim();
    await IncidentStorage.save(inc);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: ctrl, maxLines: maxLines,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'New Incident' : 'Edit Incident',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _tf('Incident Name', _name),
          DropdownButtonFormField<String>(
            initialValue: _type.isEmpty ? null : _type,
            decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder(), isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
            items: _kIncidentTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => setState(() => _type = v ?? ''),
          ),
          const SizedBox(height: 10),
          _tf('Location / Base Camp', _location),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
            items: _kIncidentStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _status = v ?? 'Active'),
          ),
          const SizedBox(height: 10),
          _tf('Notes', _notes, maxLines: 3),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(widget.existing == null ? 'Create Incident' : 'Save Changes'),
          ),
        ]),
      ),
    );
  }
}

// ── Roster Tab ────────────────────────────────────────────────────────────────

class _RosterTab extends StatefulWidget {
  const _RosterTab();
  @override
  State<_RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends State<_RosterTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<TeamMember> _members = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await RosterStorage.load();
    if (mounted) setState(() { _members = d; _loading = false; });
  }

  Future<void> _openForm([TeamMember? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MemberFormSheet(existing: existing),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Summary header: count per cert level
    final certCounts = <String, int>{};
    for (final m in _members) {
      certCounts[m.certification] = (certCounts[m.certification] ?? 0) + 1;
    }

    return Stack(
      children: [
        _members.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('No team members', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Member'),
                    onPressed: () => _openForm(),
                  ),
                ]),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                children: [
                  // Cert summary chips
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: certCounts.entries.map((e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _certColor(e.key).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Text('${e.key}: ${e.value}', style: TextStyle(fontSize: 11, color: _certColor(e.key), fontWeight: FontWeight.w600)),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  ..._members.map((m) => _memberTile(m)),
                ],
              ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'roster_fab',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add),
            label: const Text('Add Member'),
          ),
        ),
      ],
    );
  }

  Widget _memberTile(TeamMember m) {
    final certCol = _certColor(m.certification);
    final statusCol = _memberStatusColor(m.status);
    final expiring = m.isCertExpired || m.isCertExpiringSoon;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: certCol.withValues(alpha: 0.15),
              child: Text(
                m.certification.length > 4 ? m.certification.substring(0, 3) : m.certification,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: certCol),
              ),
            ),
            Positioned(
              right: -2, bottom: -2,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: statusCol, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
          ],
        ),
        title: Row(children: [
          Expanded(child: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (m.callsign.isNotEmpty) Text(m.callsign, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: statusCol.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(m.status, style: TextStyle(fontSize: 10, color: statusCol, fontWeight: FontWeight.w600)),
          ),
          if (expiring) ...[
            const SizedBox(width: 6),
            Icon(m.isCertExpired ? Icons.error : Icons.warning_amber, size: 14,
                color: m.isCertExpired ? Colors.red : Colors.orange),
            Text(m.isCertExpired ? ' Expired' : ' Expiring soon',
                style: TextStyle(fontSize: 10, color: m.isCertExpired ? Colors.red : Colors.orange)),
          ],
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(m)),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
            await RosterStorage.delete(m.id);
            _load();
          }),
        ]),
        onTap: () => _cycleStatus(m),
      ),
    );
  }

  Future<void> _cycleStatus(TeamMember m) async {
    final idx = _kMemberStatuses.indexOf(m.status);
    m.status = _kMemberStatuses[(idx + 1) % _kMemberStatuses.length];
    await RosterStorage.save(m);
    _load();
  }
}

// ── Member Form Sheet ─────────────────────────────────────────────────────────

class _MemberFormSheet extends StatefulWidget {
  final TeamMember? existing;
  const _MemberFormSheet({this.existing});
  @override
  State<_MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<_MemberFormSheet> {
  late final TextEditingController _name, _callsign, _contact, _notes, _expiry;
  String _cert = 'WFR', _status = 'Available';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _callsign = TextEditingController(text: e?.callsign ?? '');
    _contact = TextEditingController(text: e?.contact ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _expiry = TextEditingController(text: e?.certExpiry ?? '');
    _cert = e?.certification ?? 'WFR';
    _status = e?.status ?? 'Available';
  }

  @override
  void dispose() {
    for (final c in [_name, _callsign, _contact, _notes, _expiry]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final m = widget.existing ?? TeamMember.fresh();
    m.name = _name.text.trim();
    m.callsign = _callsign.text.trim();
    m.certification = _cert;
    m.certExpiry = _expiry.text.trim();
    m.contact = _contact.text.trim();
    m.status = _status;
    m.notes = _notes.text.trim();
    await RosterStorage.save(m);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: ctrl, maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'Add Team Member' : 'Edit Member',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _tf('Full Name', _name)),
            const SizedBox(width: 8),
            SizedBox(width: 110, child: _tf('Callsign', _callsign)),
          ]),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _cert,
                decoration: const InputDecoration(labelText: 'Cert Level', border: OutlineInputBorder(), isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: _kCerts.map((c) => DropdownMenuItem(
                  value: c,
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: _certColor(c), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(c),
                  ]),
                )).toList(),
                onChanged: (v) => setState(() => _cert = v ?? 'WFR'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _tf('Cert Expiry', _expiry, hint: 'YYYY-MM-DD')),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
            items: _kMemberStatuses.map((s) => DropdownMenuItem(
              value: s,
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _memberStatusColor(s), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(s),
              ]),
            )).toList(),
            onChanged: (v) => setState(() => _status = v ?? 'Available'),
          ),
          const SizedBox(height: 10),
          _tf('Contact / Radio', _contact),
          _tf('Notes', _notes, maxLines: 2),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(widget.existing == null ? 'Add Member' : 'Save'),
          ),
        ]),
      ),
    );
  }
}

// ── Tasks Tab ─────────────────────────────────────────────────────────────────

class _TasksTab extends StatefulWidget {
  const _TasksTab();
  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<OpTask> _tasks = [];
  List<TeamMember> _members = [];
  bool _loading = true;
  String _filter = 'Active';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tasks = await TaskStorage.load();
    final members = await RosterStorage.load();
    if (mounted) setState(() { _tasks = tasks; _members = members; _loading = false; });
  }

  List<OpTask> get _filtered => _tasks.where((t) {
    if (_filter == 'Active') return t.status != 'Complete';
    if (_filter == 'Complete') return t.status == 'Complete';
    return true;
  }).toList();

  Future<void> _openForm([OpTask? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TaskFormSheet(existing: existing, members: _members),
    );
    if (result == true) _load();
  }

  Future<void> _cycleStatus(OpTask t) async {
    final idx = _kTaskStatuses.indexOf(t.status);
    t.status = _kTaskStatuses[(idx + 1) % _kTaskStatuses.length];
    await TaskStorage.save(t);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    final active = _tasks.where((t) => t.status != 'Complete').length;
    final done = _tasks.where((t) => t.status == 'Complete').length;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                Text('$active active', style: TextStyle(fontWeight: FontWeight.w600, color: _taskStatusColor('In Progress'))),
                const SizedBox(width: 12),
                Text('$done done', style: TextStyle(fontWeight: FontWeight.w600, color: _taskStatusColor('Complete'))),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Active', label: Text('Active')),
                    ButtonSegment(value: 'Complete', label: Text('Done')),
                    ButtonSegment(value: 'All', label: Text('All')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.task_alt, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 8),
                        Text(_filter == 'Complete' ? 'No completed tasks' : 'No active tasks',
                            style: const TextStyle(color: Colors.grey)),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _taskTile(_filtered[i]),
                    ),
            ),
          ],
        ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'tasks_fab',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_task),
            label: const Text('New Task'),
          ),
        ),
      ],
    );
  }

  Widget _taskTile(OpTask t) {
    final pColor = _priorityColor(t.priority);
    final sColor = _taskStatusColor(t.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 4, color: pColor),
            Expanded(
              child: ListTile(
                title: Text(t.title.isEmpty ? '(untitled)' : t.title,
                    style: TextStyle(fontWeight: FontWeight.w600,
                        decoration: t.status == 'Complete' ? TextDecoration.lineThrough : null)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (t.description.isNotEmpty) Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: sColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                      child: Text(t.status, style: TextStyle(fontSize: 10, color: sColor, fontWeight: FontWeight.w600)),
                    ),
                    if (t.assignedTo.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                      Text(' ${t.assignedTo}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ]),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openForm(t)),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
                    await TaskStorage.delete(t.id);
                    _load();
                  }),
                ]),
                onTap: () => _cycleStatus(t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Task Form Sheet ───────────────────────────────────────────────────────────

class _TaskFormSheet extends StatefulWidget {
  final OpTask? existing;
  final List<TeamMember> members;
  const _TaskFormSheet({this.existing, required this.members});
  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  late final TextEditingController _title, _desc, _notes;
  String _assignedTo = '', _priority = 'Normal', _status = 'Pending';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _assignedTo = e?.assignedTo ?? '';
    _priority = e?.priority ?? 'Normal';
    _status = e?.status ?? 'Pending';
  }

  @override
  void dispose() { _title.dispose(); _desc.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    final t = widget.existing ?? OpTask.fresh();
    t.title = _title.text.trim();
    t.description = _desc.text.trim();
    t.assignedTo = _assignedTo;
    t.priority = _priority;
    t.status = _status;
    t.notes = _notes.text.trim();
    await TaskStorage.save(t);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _tf(String label, TextEditingController ctrl, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      controller: ctrl, maxLines: maxLines,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.existing == null ? 'New Task' : 'Edit Task',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _tf('Task Title', _title),
          _tf('Description', _desc, maxLines: 2),
          // Priority
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder(), isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: _kPriorities.map((p) => DropdownMenuItem(
                  value: p,
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: _priorityColor(p), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(p),
                  ]),
                )).toList(),
                onChanged: (v) => setState(() => _priority = v ?? 'Normal'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
                items: _kTaskStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _status = v ?? 'Pending'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // Assignee
          DropdownButtonFormField<String>(
            initialValue: _assignedTo.isEmpty ? null : _assignedTo,
            decoration: const InputDecoration(labelText: 'Assigned To', border: OutlineInputBorder(), isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
            items: [
              const DropdownMenuItem(value: '', child: Text('Unassigned')),
              ...widget.members.map((m) => DropdownMenuItem(
                value: m.displayName,
                child: Row(children: [_CertBadge(m.certification), const SizedBox(width: 6), Text(m.displayName)]),
              )),
            ],
            onChanged: (v) => setState(() => _assignedTo = v ?? ''),
          ),
          const SizedBox(height: 10),
          _tf('Notes', _notes, maxLines: 2),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(widget.existing == null ? 'Create Task' : 'Save'),
          ),
        ]),
      ),
    );
  }
}

// ── Handoff Tab ───────────────────────────────────────────────────────────────

class _HandoffTab extends StatefulWidget {
  const _HandoffTab();
  @override
  State<_HandoffTab> createState() => _HandoffTabState();
}

class _HandoffTabState extends State<_HandoffTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<ShiftHandoff> _handoffs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final d = await HandoffStorage.load();
    if (mounted) setState(() { _handoffs = d; _loading = false; });
  }

  Future<void> _openForm([ShiftHandoff? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _HandoffFormScreen(existing: existing)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        _handoffs.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.handshake_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('No handoffs on record', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New Handoff'),
                    onPressed: () => _openForm(),
                  ),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                itemCount: _handoffs.length,
                itemBuilder: (_, i) {
                  final h = _handoffs[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0x1A3F51B5),
                        child: Icon(Icons.handshake_outlined, color: Colors.indigo, size: 20),
                      ),
                      title: Text('${h.outgoingLead.isEmpty ? "?" : h.outgoingLead} → ${h.incomingLead.isEmpty ? "?" : h.incomingLead}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(h.timeDisplay, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        if (h.incidentStatus.isNotEmpty)
                          Text(h.incidentStatus, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ]),
                      isThreeLine: h.incidentStatus.isNotEmpty,
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 18),
                          onPressed: () => SharePlus.instance.share(ShareParams(
                            text: h.formattedText,
                            subject: 'Shift Handoff — ${h.timeDisplay}',
                          )),
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), onPressed: () async {
                          await HandoffStorage.delete(h.id);
                          _load();
                        }),
                      ]),
                      onTap: () => _openForm(h),
                    ),
                  );
                },
              ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'handoff_fab',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('New Handoff'),
          ),
        ),
      ],
    );
  }
}

// ── Handoff Form Screen ───────────────────────────────────────────────────────

class _HandoffFormScreen extends StatefulWidget {
  final ShiftHandoff? existing;
  const _HandoffFormScreen({this.existing});
  @override
  State<_HandoffFormScreen> createState() => _HandoffFormScreenState();
}

class _HandoffFormScreenState extends State<_HandoffFormScreen> {
  late final TextEditingController _outgoing, _incoming, _incStatus,
      _ptStatus, _teamStatus, _tasks, _critical, _resources, _notes;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _outgoing = TextEditingController(text: e?.outgoingLead ?? '');
    _incoming = TextEditingController(text: e?.incomingLead ?? '');
    _incStatus = TextEditingController(text: e?.incidentStatus ?? '');
    _ptStatus = TextEditingController(text: e?.patientStatus ?? '');
    _teamStatus = TextEditingController(text: e?.teamStatus ?? '');
    _tasks = TextEditingController(text: e?.pendingTasks ?? '');
    _critical = TextEditingController(text: e?.criticalInfo ?? '');
    _resources = TextEditingController(text: e?.resourceStatus ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [_outgoing, _incoming, _incStatus, _ptStatus, _teamStatus, _tasks, _critical, _resources, _notes]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final h = widget.existing ?? ShiftHandoff.fresh();
    h.outgoingLead = _outgoing.text.trim();
    h.incomingLead = _incoming.text.trim();
    h.incidentStatus = _incStatus.text.trim();
    h.patientStatus = _ptStatus.text.trim();
    h.teamStatus = _teamStatus.text.trim();
    h.pendingTasks = _tasks.text.trim();
    h.criticalInfo = _critical.text.trim();
    h.resourceStatus = _resources.text.trim();
    h.notes = _notes.text.trim();
    await HandoffStorage.save(h);
    if (mounted) Navigator.pop(context);
  }

  Widget _section(String label, Color accent, TextEditingController ctrl, {int maxLines = 3, String? hint}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: accent)),
        const SizedBox(height: 8),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(h == null ? 'New Shift Handoff' : 'Edit Handoff'),
        actions: [
          if (h != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: _buildPreview(),
                subject: 'Shift Handoff',
              )),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              onPressed: _save,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Leader row
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Expanded(child: TextFormField(
                controller: _outgoing,
                decoration: const InputDecoration(labelText: 'Outgoing Lead', border: OutlineInputBorder(), isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
              )),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, color: Colors.indigo)),
              Expanded(child: TextFormField(
                controller: _incoming,
                decoration: const InputDecoration(labelText: 'Incoming Lead', border: OutlineInputBorder(), isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
              )),
            ]),
          ),
          _section('[1] Incident Status', Colors.indigo, _incStatus,
              hint: 'Current situation, scene status, ICS assignments…'),
          _section('[2] Patient Status', Colors.red, _ptStatus,
              hint: 'Patient count, conditions, treatments given, pending…'),
          _section('[3] Team / Personnel', Colors.teal, _teamStatus,
              hint: 'Team members on duty, fatigue levels, injuries…'),
          _section('[4] Outstanding Tasks', Colors.orange, _tasks,
              hint: 'Tasks pending handoff, priorities, deadlines…'),
          _section('[5] Critical Information', Colors.purple, _critical,
              hint: 'Safety hazards, weather, comms freqs, access routes…'),
          _section('[6] Resources / Logistics', Colors.green, _resources,
              hint: 'Equipment status, fuel, medical supplies, food/water…'),
          _section('Notes', Colors.grey, _notes, hint: 'Any other relevant notes…', maxLines: 4),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  String _buildPreview() {
    final h = widget.existing ?? ShiftHandoff.fresh();
    h.outgoingLead = _outgoing.text.trim();
    h.incomingLead = _incoming.text.trim();
    h.incidentStatus = _incStatus.text.trim();
    h.patientStatus = _ptStatus.text.trim();
    h.teamStatus = _teamStatus.text.trim();
    h.pendingTasks = _tasks.text.trim();
    h.criticalInfo = _critical.text.trim();
    h.resourceStatus = _resources.text.trim();
    h.notes = _notes.text.trim();
    return h.formattedText;
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _CertBadge extends StatelessWidget {
  final String cert;
  const _CertBadge(this.cert);

  @override
  Widget build(BuildContext context) {
    final color = _certColor(cert);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
      child: Text(cert.length > 4 ? cert.substring(0, 4) : cert,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
