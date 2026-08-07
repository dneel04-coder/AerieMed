import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService, ProtocolSyncService, DeploymentOrder, DeploymentOrderService, TeamProtocolsScreen, showReadAcknowledgment, AdminAlertService;
import 'user_profile.dart' show LoginScreen;

enum _CertExpiry { green, yellow, red }

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

Color _vaultCertColor(String type) {
  switch (type) {
    case 'CPR/AED': return const Color(0xFF1976D2);
    case 'BLS':     return const Color(0xFF0288D1);
    case 'ACLS':    return const Color(0xFFE65100);
    case 'PALS':    return const Color(0xFFF57C00);
    case 'PHTLS':
    case 'ITLS':
    case 'TCCC':    return const Color(0xFF6D4C41);
    case 'EMR':     return const Color(0xFF388E3C);
    case 'EMT':     return const Color(0xFF2E7D32);
    case 'AEMT':    return const Color(0xFF00695C);
    case 'Paramedic': return const Color(0xFFC62828);
    case 'NREMT':   return const Color(0xFF00897B);
    case 'RN':      return const Color(0xFF7B1FA2);
    case 'LPN':     return const Color(0xFF9C27B0);
    case 'NP':      return const Color(0xFF512DA8);
    case 'PA':      return const Color(0xFF4527A0);
    case 'MD/DO':   return const Color(0xFF283593);
    default:        return Colors.grey;
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
  String compiledBy, incidentLead;
  List<String> membersPresent;
  List<IcRole> roles;
  bool locked; // archived incidents are locked; admin can unlock for editing

  Incident({
    required this.id,
    required this.startedAt,
    this.name = '',
    this.type = '',
    this.location = '',
    this.status = 'Active',
    this.notes = '',
    this.compiledBy = '',
    this.incidentLead = '',
    List<String>? membersPresent,
    List<IcRole>? roles,
    this.locked = false,
  }) : membersPresent = membersPresent ?? [],
       roles = roles ?? _defaultRoles();

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
        'compiledBy': compiledBy, 'incidentLead': incidentLead,
        'membersPresent': membersPresent,
        'roles': roles.map((r) => r.toJson()).toList(),
        'locked': locked,
      };

  factory Incident.fromJson(Map<String, dynamic> j) => Incident(
        id: j['id'] as String? ?? '',
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        location: j['location'] as String? ?? '',
        status: j['status'] as String? ?? 'Active',
        notes: j['notes'] as String? ?? '',
        compiledBy: j['compiledBy'] as String? ?? '',
        incidentLead: j['incidentLead'] as String? ?? '',
        membersPresent: (j['membersPresent'] as List? ?? []).cast<String>(),
        roles: (j['roles'] as List? ?? [])
            .map((e) => IcRole.fromJson(e as Map<String, dynamic>))
            .toList(),
        locked: j['locked'] as bool? ?? false,
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


// ── Dashboard ─────────────────────────────────────────────────────────────────

class TeamCommandScreen extends StatefulWidget {
  const TeamCommandScreen({super.key});

  @override
  State<TeamCommandScreen> createState() => _TeamCommandScreenState();
}

class _TeamCommandScreenState extends State<TeamCommandScreen> {
  List<Map<String, dynamic>> _profiles = [];
  Map<String, String> _todayAvailability = {};
  List<DeploymentOrder> _unreadOrders = [];
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    ProtocolSyncService.instance.isAdminMode
        .then((v) { if (mounted) setState(() => _isAdmin = v); });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) { if (mounted) setState(() => _loading = false); return; }
    try {
      final client = SupabaseService.client!;
      final today = DateTime.now();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final profilesRaw = await client.from('user_profiles').select('user_id, name, callsign') as List;
      final availRaw = await client.from('team_availability').select('user_id, status').eq('date', dateStr) as List;
      final unread = await ProtocolSyncService.instance.pendingDeploymentOrders();
      final avail = <String, String>{};
      for (final r in availRaw) {
        avail[r['user_id'] as String] = r['status'] as String? ?? 'Available';
      }
      if (mounted) setState(() {
        _profiles = List<Map<String, dynamic>>.from(profilesRaw);
        _todayAvailability = avail;
        _unreadOrders = unread;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(List<String> statuses) => _profiles.where((p) {
        final s = _todayAvailability[p['user_id'] as String] ?? 'Available';
        return statuses.contains(s);
      }).length;

  void _openFull([int tab = 0]) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => _TeamCommandTabs(initialTab: tab)));

  void _openSection(String title, Widget content) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: content,
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final available = _count(['Available', 'Partial']);
    final deployed  = _count(['Deployed']);
    final offDuty   = _count(['Unavailable']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Command'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Full Command View',
            onPressed: () => _openFull(),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // ── Stat chips ────────────────────────────────────────────
                  Row(children: [
                    Expanded(child: _StatChip('Available', available,
                        const Color(0xFF2E7D32), Icons.check_circle_outline)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatChip('Deployed', deployed,
                        const Color(0xFF1565C0), Icons.flight_takeoff_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _StatChip('Off-Duty', offDuty,
                        Colors.grey, Icons.do_not_disturb_outlined)),
                  ]),
                  const SizedBox(height: 16),

                  // ── Unread orders banner ──────────────────────────────────
                  if (_unreadOrders.isNotEmpty)
                    GestureDetector(
                      onTap: () => _openFull(4),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.6)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Stack(children: [
                            const Icon(Icons.assignment_outlined,
                                color: Colors.orange, size: 28),
                            Positioned(
                              top: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle),
                                child: Text('${_unreadOrders.length}',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                '${_unreadOrders.length} Unread Deployment Order${_unreadOrders.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange)),
                              Text(_unreadOrders.first.title,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          const Icon(Icons.chevron_right,
                              color: Colors.orange),
                        ]),
                      ),
                    ),

                  // ── QuickDeploy button ────────────────────────────────────
                  _QuickDeployButton(
                    isAdmin: _isAdmin,
                    onTap: () => _openFull(_isAdmin ? 4 : 5),
                  ),
                  const SizedBox(height: 24),

                  // ── Command sections ──────────────────────────────────────
                  const _SectionHeader('Command'),
                  _CommandNavTile(Icons.account_tree_outlined,
                      'Incident Command',
                      () => _openSection('Incident Command', const _IncidentTab())),
                  _CommandNavTile(Icons.people_outlined,
                      'Roster & Profiles',
                      () => _openSection('Roster & Profiles', const _RosterTab())),
                  _CommandNavTile(Icons.assignment_outlined,
                      'Deployment Orders',
                      () => _openSection('Deployment Orders', _DeploymentOrdersTab())),
                  _CommandNavTile(Icons.calendar_month_outlined,
                      'Availability Calendar',
                      () => _openSection('Availability Calendar', _AvailabilityTab())),
                  _CommandNavTile(Icons.description_outlined,
                      'Team Protocols',
                      () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const TeamProtocolsScreen()))),
                  _CommandNavTile(Icons.more_horiz,
                      'Full Command View (Tasks, Handoff & more)',
                      () => _openFull()),
                ],
              ),
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _StatChip(this.label, this.count, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text('$count',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 11, color: color),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

class _QuickDeployButton extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onTap;
  const _QuickDeployButton({required this.isAdmin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        icon: const Icon(Icons.flight_takeoff, size: 22),
        label: Text(isAdmin ? '⚡  Push Deployment Order' : '⚡  Set My Status'),
        onPressed: onTap,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _CommandNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CommandNavTile(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        dense: true,
      ),
    );
  }
}


// ── Full tabbed command view ──────────────────────────────────────────────────

class _TeamCommandTabs extends StatelessWidget {
  final int initialTab;
  const _TeamCommandTabs({this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Team Command'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.account_tree_outlined, size: 20), text: 'Incident'),
              Tab(icon: Icon(Icons.people_outlined, size: 20), text: 'Roster'),
              Tab(icon: Icon(Icons.task_alt, size: 20), text: 'Tasks'),
              Tab(icon: Icon(Icons.handshake_outlined, size: 20), text: 'Handoff'),
              Tab(icon: Icon(Icons.assignment_outlined, size: 20), text: 'Orders'),
              Tab(icon: Icon(Icons.calendar_month_outlined, size: 20), text: 'Availability'),
            ],
          ),
        ),
        body: TabBarView(children: [
          const _IncidentTab(),
          const _RosterTab(),
          const _TasksTab(),
          const _HandoffTab(),
          _DeploymentOrdersTab(),
          _AvailabilityTab(),
        ]),
      ),
    );
  }
}


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
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
    ProtocolSyncService.instance.isAdminMode
        .then((v) { if (mounted) setState(() => _isAdmin = v); });
  }

  Future<void> _load() async {
    final d = await IncidentStorage.load();
    if (mounted) setState(() { _incidents = d; _loading = false; });
  }

  void _viewArchivedIncident(Incident inc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(children: [
              Expanded(child: Text(inc.displayTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 13, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(inc.status, style: const TextStyle(fontSize: 11,
                      color: Colors.orange, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 4),
            Text(inc.timeDisplay, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const Divider(height: 24),
            if (inc.type.isNotEmpty) _incRow('Type', inc.type),
            if (inc.location.isNotEmpty) _incRow('Location', inc.location),
            if (inc.compiledBy.isNotEmpty) _incRow('Compiled by', inc.compiledBy),
            if (inc.incidentLead.isNotEmpty) _incRow('Lead', inc.incidentLead),
            if (inc.membersPresent.isNotEmpty)
              _incRow('Personnel', inc.membersPresent.join(', ')),
            if (inc.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(inc.notes, style: const TextStyle(fontSize: 13)),
            ],
            if (inc.roles.any((r) => r.assignedTo.isNotEmpty)) ...[
              const Divider(height: 24),
              const Text('IC STRUCTURE', style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 11, color: Colors.grey, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ...inc.roles.where((r) => r.assignedTo.isNotEmpty).map((r) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Expanded(child: Text(r.title,
                          style: const TextStyle(fontSize: 12, color: Colors.grey))),
                      Text(r.assignedTo,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  )),
            ],
            const SizedBox(height: 16),
            if (_isAdmin && inc.locked)
              FilledButton.icon(
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Unlock for Editing'),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.pop(context);
                  inc.locked = false;
                  IncidentStorage.save(inc).then((_) => _load());
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _incRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 100,
          child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]),
  );

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
              ..._incidents.where((i) => i.status != 'Active').map((inc) {
                final isLocked = inc.locked;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.withValues(alpha: 0.15),
                      child: Icon(isLocked ? Icons.lock_outline : Icons.folder_outlined,
                          color: isLocked ? Colors.orange : Colors.grey, size: 20),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(inc.displayTitle)),
                      if (isLocked)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Tooltip(
                            message: 'Locked — admin can unlock to edit',
                            child: Icon(Icons.lock, size: 13, color: Colors.orange),
                          ),
                        ),
                    ]),
                    subtitle: Text('${inc.status}  •  ${inc.timeDisplay}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      // View always available
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        tooltip: 'View incident',
                        onPressed: () => _viewArchivedIncident(inc),
                      ),
                      if (!isLocked) ...[
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _openForm(inc)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () async {
                            await IncidentStorage.delete(inc.id);
                            _load();
                          }),
                      ] else if (_isAdmin)
                        IconButton(
                          icon: const Icon(Icons.lock_open_outlined, size: 18, color: Colors.orange),
                          tooltip: 'Unlock for editing',
                          onPressed: () async {
                            inc.locked = false;
                            await IncidentStorage.save(inc);
                            _load();
                          }),
                    ]),
                    onTap: () => _viewArchivedIncident(inc),
                  ),
                );
              }),
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
          if (inc.compiledBy.isNotEmpty || inc.incidentLead.isNotEmpty) ...[
            const Divider(height: 10),
            if (inc.compiledBy.isNotEmpty)
              Row(children: [
                const Icon(Icons.edit_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Compiled by: ${inc.compiledBy}', style: const TextStyle(fontSize: 12)),
              ]),
            if (inc.incidentLead.isNotEmpty)
              Row(children: [
                const Icon(Icons.star_outline, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Lead: ${inc.incidentLead}', style: const TextStyle(fontSize: 12)),
              ]),
          ],
          if (inc.membersPresent.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 2,
              children: [
                const Icon(Icons.people_outline, size: 13, color: Colors.grey),
                ...inc.membersPresent.map((m) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m, style: const TextStyle(fontSize: 11)),
                )),
              ]),
          ],
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


class _IncidentFormSheet extends StatefulWidget {
  final Incident? existing;
  const _IncidentFormSheet({this.existing});
  @override
  State<_IncidentFormSheet> createState() => _IncidentFormSheetState();
}

class _IncidentFormSheetState extends State<_IncidentFormSheet> {
  late final TextEditingController _name, _location, _notes;
  String _type = '', _status = 'Active';
  String _compiledBy = '', _incidentLead = '';
  List<String> _membersPresent = [];
  List<String> _profileNames = [];
  bool _profilesLoading = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name     = TextEditingController(text: e?.name ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes    = TextEditingController(text: e?.notes ?? '');
    _type         = e?.type ?? '';
    _status       = e?.status ?? 'Active';
    _compiledBy   = e?.compiledBy ?? '';
    _incidentLead = e?.incidentLead ?? '';
    _membersPresent = List<String>.from(e?.membersPresent ?? []);
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      // Pre-fill compiled by from own profile
      if (_compiledBy.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        _compiledBy = prefs.getString('tac_callsign') ?? '';
      }
      final ok = await SupabaseService.ensureInitialized();
      if (!ok) { if (mounted) setState(() => _profilesLoading = false); return; }
      final rows = await SupabaseService.client!
          .from('user_profiles')
          .select('name, callsign')
          .order('name') as List;
      final names = rows.map<String>((p) {
        final name = p['name'] as String? ?? '';
        final callsign = p['callsign'] as String? ?? '';
        return callsign.isNotEmpty ? '$name ($callsign)' : name;
      }).where((s) => s.trim().isNotEmpty).toList();
      if (mounted) setState(() { _profileNames = names; _profilesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _profilesLoading = false);
    }
  }

  @override
  void dispose() { _name.dispose(); _location.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _save() async {
    final inc = widget.existing ?? Incident.fresh();
    inc.name           = _name.text.trim();
    inc.type           = _type;
    inc.location       = _location.text.trim();
    inc.status         = _status;
    inc.notes          = _notes.text.trim();
    inc.compiledBy     = _compiledBy;
    inc.incidentLead   = _incidentLead;
    inc.membersPresent = _membersPresent;
    // Auto-lock when incident is archived (non-Active status).
    if (_status != 'Active') inc.locked = true;
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

  Widget _personDropdown(String label, String value, ValueChanged<String?> onChanged) {
    final items = _profileNames.isNotEmpty
        ? _profileNames
        : (value.isNotEmpty ? [value] : <String>[]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: value.isEmpty ? null : value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          suffixIcon: _profilesLoading
              ? const SizedBox(width: 18, height: 18,
                  child: Padding(padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : null,
        ),
        items: items.map((n) => DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }

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
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('PERSONNEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12,
                color: Colors.grey, letterSpacing: 0.8)),
          ),
          _personDropdown('Compiled by', _compiledBy,
              (v) => setState(() => _compiledBy = v ?? '')),
          _personDropdown('Incident Lead', _incidentLead,
              (v) => setState(() => _incidentLead = v ?? '')),
          // Members present — tap chips to toggle
          const Text('Members Present', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          if (_profileNames.isEmpty && _profilesLoading)
            const Center(child: SizedBox(height: 24, width: 24,
                child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_profileNames.isEmpty)
            const Text('No profiles loaded', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            Wrap(spacing: 6, runSpacing: 4, children: _profileNames.map((name) {
              final selected = _membersPresent.contains(name);
              return FilterChip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (v) => setState(() => v
                    ? _membersPresent.add(name)
                    : _membersPresent.remove(name)),
                selectedColor: Colors.indigo.withValues(alpha: 0.2),
                checkmarkColor: Colors.indigo,
              );
            }).toList()),
          const Divider(),
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


class _RosterTab extends StatefulWidget {
  const _RosterTab();
  @override
  State<_RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends State<_RosterTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Members view
  List<TeamMember> _members = [];
  bool _loading = true;

  // Team Certs view
  List<Map<String, dynamic>> _certRows = [];
  bool _certLoading = false;
  bool _certNotConfigured = false;
  final _stateSearch = TextEditingController();

  // Profiles view
  List<Map<String, dynamic>> _profileRows = [];
  bool _profileLoading = false;
  bool _profileNotConfigured = false;

  // Full name lookup used by Team Certs (userId → name)
  Map<String, String> _userNames = {};

  // Today's availability: userId → status ('Available', 'Unavailable', 'Partial', 'Deployed')
  Map<String, String> _todayAvailability = {};

  bool _isAdmin = false;
  String _myUserId = '';
  int _viewIdx = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProfiles();
    _loadTodayAvailability();
    ProtocolSyncService.instance.isAdminMode.then((v) {
      if (mounted) setState(() => _isAdmin = v);
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _myUserId = p.getString('tac_user_id') ?? '');
    });
  }

  Future<void> _loadTodayAvailability() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) return;
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final rows = await SupabaseService.client!
          .from('team_availability')
          .select('user_id, status')
          .eq('date', dateStr) as List;
      final map = <String, String>{};
      for (final r in rows) {
        map[r['user_id'] as String] = r['status'] as String? ?? 'Available';
      }
      if (mounted) setState(() => _todayAvailability = map);
    } catch (_) {}
  }

  @override
  void dispose() { _stateSearch.dispose(); super.dispose(); }

  Future<void> _load() async {
    final d = await RosterStorage.load();
    if (mounted) setState(() { _members = d; _loading = false; });
  }

  Future<void> _loadCerts() async {
    if (_certLoading) return;
    setState(() { _certLoading = true; _certNotConfigured = false; });
    try {
      final ok = await SupabaseService.ensureInitialized();
      if (!ok) {
        if (mounted) setState(() { _certLoading = false; _certNotConfigured = true; });
        return;
      }
      final client = SupabaseService.client!;
      final certsFuture = ProtocolSyncService.instance.adminGetCerts();
      final profilesFuture = client.from('user_profiles').select('user_id, name');
      final certs = await certsFuture;
      final profiles = await profilesFuture as List;
      final names = <String, String>{};
      for (final p in profiles) {
        final uid = p['user_id'] as String? ?? '';
        final name = p['name'] as String? ?? '';
        if (uid.isNotEmpty && name.isNotEmpty) names[uid] = name;
      }
      if (mounted) setState(() { _certRows = certs; _userNames = names; _certLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _certLoading = false; _certNotConfigured = true; });
    }
  }

  Future<void> _loadProfiles() async {
    if (_profileLoading) return;
    setState(() { _profileLoading = true; _profileNotConfigured = false; });
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) {
      if (mounted) setState(() { _profileLoading = false; _profileNotConfigured = true; });
      return;
    }
    try {
      final rows = await SupabaseService.client!
          .from('user_profiles')
          .select()
          .order('name');
      final list = List<Map<String, dynamic>>.from(rows as List);
      final names = <String, String>{};
      for (final p in list) {
        final uid = p['user_id'] as String? ?? '';
        final name = p['name'] as String? ?? '';
        if (uid.isNotEmpty) names[uid] = name;
      }
      if (mounted) setState(() {
        _profileRows = list;
        _userNames = names;
        _profileLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _profileLoading = false; _profileNotConfigured = true; });
    }
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0,
                icon: Icon(Icons.people_outline, size: 16), label: Text('Members')),
            ButtonSegment(value: 1,
                icon: Icon(Icons.badge_outlined, size: 16), label: Text('Team Certs')),
            ButtonSegment(value: 2,
                icon: Icon(Icons.account_circle_outlined, size: 16), label: Text('Profiles')),
          ],
          selected: {_viewIdx},
          onSelectionChanged: (s) {
            setState(() => _viewIdx = s.first);
            if (s.first == 1 && _certRows.isEmpty && !_certLoading) _loadCerts();
            if (s.first == 2 && _profileRows.isEmpty && !_profileLoading) _loadProfiles();
          },
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ),
      Expanded(child: _viewIdx == 0
          ? _buildMembersView()
          : _viewIdx == 1
              ? _buildCertsView()
              : _buildProfilesView()),
    ]);
  }

  Widget _buildMembersView() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Bucket profiles by today's availability status.
    final available   = <Map<String, dynamic>>[];
    final unavailable = <Map<String, dynamic>>[];
    final deployed    = <Map<String, dynamic>>[];

    for (final p in _profileRows) {
      final uid    = p['user_id'] as String? ?? '';
      final status = _todayAvailability[uid] ?? 'Available';
      if (status == 'Deployed') {
        deployed.add(p);
      } else if (status == 'Available' || status == 'Partial') {
        available.add(p);
      } else {
        unavailable.add(p);
      }
    }
    // Users with no profile row default to Available.

    final certCounts = <String, int>{};
    for (final m in _members) {
      certCounts[m.certification] = (certCounts[m.certification] ?? 0) + 1;
    }

    return Stack(children: [
      RefreshIndicator(
        onRefresh: () async { _loadProfiles(); _loadTodayAvailability(); },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          children: [
            if (_profileRows.isEmpty && _members.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  const Text('No team members yet', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('Members appear here when users log in',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
            if (_profileRows.isNotEmpty) ...[
              _availabilityDrawer('Available', Colors.green,
                  Icons.check_circle_outline, available),
              const SizedBox(height: 6),
              _availabilityDrawer('Unavailable', Colors.grey,
                  Icons.do_not_disturb_outlined, unavailable),
              const SizedBox(height: 6),
              _availabilityDrawer('Deployed', Colors.blue,
                  Icons.flight_takeoff_outlined, deployed),
              const SizedBox(height: 12),
            ],
            if (_members.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Manually Added',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              if (certCounts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 6, runSpacing: 4,
                    children: certCounts.entries.map((e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _certColor(e.key).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text('${e.key}: ${e.value}',
                          style: TextStyle(fontSize: 11, color: _certColor(e.key),
                              fontWeight: FontWeight.w600)),
                    )).toList(),
                  ),
                ),
              ..._members.map((m) => _memberTile(m)),
            ],
          ],
        ),
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
    ]);
  }

  Widget _availabilityDrawer(
    String title, Color color, IconData icon,
    List<Map<String, dynamic>> profiles,
  ) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text('${profiles.length} member${profiles.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
        collapsedBackgroundColor: color.withValues(alpha: 0.05),
        backgroundColor: color.withValues(alpha: 0.03),
        initiallyExpanded: title == 'Available' || title == 'Deployed',
        children: profiles.isEmpty
            ? [Padding(
                padding: const EdgeInsets.all(14),
                child: Text('None', style: TextStyle(color: Colors.grey[500])),
              )]
            : profiles.map((p) {
                final name     = p['name'] as String? ?? '';
                final callsign = p['callsign'] as String? ?? '';
                final certLvl  = p['cert_level'] as String? ?? 'None';
                final display  = name.isNotEmpty ? name : callsign;
                final sub      = (callsign.isNotEmpty && name.isNotEmpty)
                    ? 'Callsign: $callsign'
                    : null;
                final col = _certColor(certLvl);
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 15,
                    backgroundColor: col.withValues(alpha: 0.15),
                    child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: col)),
                  ),
                  title: Text(display,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: sub != null
                      ? Text(sub, style: const TextStyle(fontSize: 12))
                      : null,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.12),
                      border: Border.all(color: col.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(certLvl,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: col)),
                  ),
                );
              }).toList(),
      ),
    );
  }

  // Returns expiration status from a Supabase cert row.
  static _CertExpiry _rowExpiry(Map<String, dynamic> row) {
    final s = row['expiration_date'] as String?;
    if (s == null || s.isEmpty) return _CertExpiry.green;
    final exp = DateTime.tryParse(s);
    if (exp == null) return _CertExpiry.green;
    final days = exp.difference(DateTime.now()).inDays;
    if (days < 0) return _CertExpiry.red;
    if (days <= 365) return _CertExpiry.yellow;
    return _CertExpiry.green;
  }

  Widget _buildCertsView() {
    if (_certLoading) return const Center(child: CircularProgressIndicator());
    if (_certNotConfigured) return _notConfiguredWidget();

    if (_certRows.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.badge_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        const Text('No certs uploaded yet', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          onPressed: _loadCerts,
        ),
      ]));
    }

    return _isAdmin ? _buildAdminCertsView() : _buildAllUserCertsView();
  }

  // All users see certs grouped by person.
  Widget _buildAllUserCertsView() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final displayMap = <String, String>{};
    for (final r in _certRows) {
      final uid = r['user_id'] as String? ?? '';
      grouped.putIfAbsent(uid, () => []).add(r);
      final name = _userNames[uid] ?? '';
      final callsign = r['callsign'] as String? ?? '';
      displayMap[uid] = name.isNotEmpty ? name : (callsign.isNotEmpty ? callsign : 'Unknown');
    }
    final sorted = grouped.keys.toList()
      ..sort((a, b) => displayMap[a]!.compareTo(displayMap[b]!));

    return RefreshIndicator(
      onRefresh: _loadCerts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: sorted.map((uid) => _userCertExpansion(
          displayMap[uid]!, grouped[uid]!)).toList(),
      ),
    );
  }

  // Admin sees three colored status drawers.
  Widget _buildAdminCertsView() {
    final green  = <String, List<Map<String, dynamic>>>{};
    final yellow = <String, List<Map<String, dynamic>>>{};
    final red    = <String, List<Map<String, dynamic>>>{};
    final displayMap = <String, String>{};

    for (final r in _certRows) {
      final uid = r['user_id'] as String? ?? '';
      final name = _userNames[uid] ?? '';
      final callsign = r['callsign'] as String? ?? '';
      displayMap[uid] = name.isNotEmpty ? name : (callsign.isNotEmpty ? callsign : 'Unknown');
      switch (_rowExpiry(r)) {
        case _CertExpiry.green:  green.putIfAbsent(uid, () => []).add(r); break;
        case _CertExpiry.yellow: yellow.putIfAbsent(uid, () => []).add(r); break;
        case _CertExpiry.red:    red.putIfAbsent(uid, () => []).add(r); break;
      }
    }

    // Count yellow+red for alert banner
    final alertCount = yellow.values.fold(0, (s, l) => s + l.length)
                     + red.values.fold(0, (s, l) => s + l.length);

    return RefreshIndicator(
      onRefresh: _loadCerts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (alertCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '$alertCount cert${alertCount == 1 ? '' : 's'} require attention '
                  '(${yellow.values.fold(0,(s,l)=>s+l.length)} expiring soon, '
                  '${red.values.fold(0,(s,l)=>s+l.length)} expired)',
                  style: const TextStyle(fontSize: 13, color: Colors.orange,
                      fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          _statusDrawer('Good Standing — >1 Year',
              Colors.green, Icons.check_circle_outline, green, displayMap),
          const SizedBox(height: 8),
          _statusDrawer('Expiring Within 1 Year',
              Colors.orange, Icons.warning_amber_rounded, yellow, displayMap),
          const SizedBox(height: 8),
          _statusDrawer('Expired',
              Colors.red, Icons.cancel_outlined, red, displayMap),
        ],
      ),
    );
  }

  Widget _statusDrawer(
    String title, Color color, IconData icon,
    Map<String, List<Map<String, dynamic>>> byUser,
    Map<String, String> displayMap,
  ) {
    final total = byUser.values.fold(0, (s, l) => s + l.length);
    final sorted = byUser.keys.toList()
      ..sort((a, b) => displayMap[a]!.compareTo(displayMap[b]!));
    return Card(
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        subtitle: Text('$total cert${total == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
        collapsedBackgroundColor: color.withValues(alpha: 0.06),
        backgroundColor: color.withValues(alpha: 0.04),
        initiallyExpanded: color == Colors.orange || color == Colors.red,
        children: sorted.isEmpty
            ? [Padding(
                padding: const EdgeInsets.all(16),
                child: Text('None', style: TextStyle(color: Colors.grey[500])),
              )]
            : sorted.map((uid) =>
                _userCertExpansion(displayMap[uid]!, byUser[uid]!,
                    indent: true)).toList(),
      ),
    );
  }

  Widget _userCertExpansion(String displayName, List<Map<String, dynamic>> certs,
      {bool indent = false}) {
    return ExpansionTile(
      tilePadding: EdgeInsets.symmetric(horizontal: indent ? 24 : 16, vertical: 0),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer)),
      ),
      title: Text(displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('${certs.length} cert${certs.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11)),
      children: certs.map((cert) {
        final type  = cert['license_type'] as String? ?? '';
        final state = cert['state'] as String? ?? '';
        final expiry = _rowExpiry(cert);
        final expStr = cert['expiration_date'] as String?;
        DateTime? expDate;
        try { if (expStr != null) expDate = DateTime.parse(expStr); } catch (_) {}
        final expiryColor = expiry == _CertExpiry.red
            ? Colors.red
            : expiry == _CertExpiry.yellow
                ? Colors.orange
                : Colors.green;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: indent ? 40 : 24),
          leading: Icon(Icons.workspace_premium,
              color: _vaultCertColor(type), size: 20),
          title: Text('$type${state.isNotEmpty ? ' — $state' : ''}',
              style: const TextStyle(fontSize: 13)),
          trailing: expDate == null
              ? const Icon(Icons.remove, size: 14, color: Colors.grey)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(expiry == _CertExpiry.red
                      ? Icons.cancel_outlined
                      : expiry == _CertExpiry.yellow
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      color: expiryColor, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${expDate.month}/${expDate.day}/${expDate.year}',
                    style: TextStyle(fontSize: 11, color: expiryColor,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
        );
      }).toList(),
    );
  }

  Widget _buildProfilesView() {
    if (_profileLoading) return const Center(child: CircularProgressIndicator());
    if (_profileNotConfigured) return _notConfiguredWidget();
    if (_profileRows.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.account_circle_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 12),
        const Text('No profiles synced yet', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          onPressed: _loadProfiles,
        ),
      ]));
    }
    // Detect duplicates: multiple rows with the same name.
    final nameCount = <String, int>{};
    for (final p in _profileRows) {
      final n = (p['name'] as String? ?? '').toLowerCase().trim();
      if (n.isNotEmpty) nameCount[n] = (nameCount[n] ?? 0) + 1;
    }
    final hasDuplicates = nameCount.values.any((c) => c > 1);

    return RefreshIndicator(
      onRefresh: _loadProfiles,
      child: Column(children: [
        if (_isAdmin && hasDuplicates)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text(
                'Duplicate profiles detected (same name, different device ID)',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              )),
              TextButton(
                onPressed: _removeDuplicateProfiles,
                child: const Text('Clean Up', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: _profileRows.length,
            itemBuilder: (_, i) => _profileCard(_profileRows[i]),
          ),
        ),
      ]),
    );
  }

  Future<void> _removeDuplicateProfiles() async {
    final client = SupabaseService.client;
    if (client == null) return;

    // Fetch which user_ids have certs so we never delete an active uploader.
    Set<String> usersWithCerts = {};
    try {
      final rows = await client.from('team_certs').select('user_id') as List;
      usersWithCerts = rows.map((r) => r['user_id'] as String).toSet();
    } catch (_) {}

    // Group by name (case-insensitive).
    final byName = <String, List<Map<String, dynamic>>>{};
    for (final p in _profileRows) {
      final key = (p['name'] as String? ?? '').toLowerCase().trim();
      if (key.isNotEmpty) byName.putIfAbsent(key, () => []).add(p);
    }

    int removed = 0;
    for (final group in byName.values) {
      if (group.length <= 1) continue;
      // Sort: cert-holders first, then by most recently updated.
      group.sort((a, b) {
        final aUid = a['user_id'] as String? ?? '';
        final bUid = b['user_id'] as String? ?? '';
        final aHasCerts = usersWithCerts.contains(aUid);
        final bHasCerts = usersWithCerts.contains(bUid);
        if (aHasCerts && !bHasCerts) return -1;
        if (!aHasCerts && bHasCerts) return 1;
        final da = DateTime.tryParse(a['updated_at'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['updated_at'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da); // newest first
      });
      // Keep index 0 (cert-holder or most recent); delete the rest.
      for (final old in group.skip(1)) {
        final oldUid = old['user_id'] as String? ?? '';
        // Safety: never delete a user who has certs attached.
        if (usersWithCerts.contains(oldUid)) continue;
        try {
          await client.from('user_profiles').delete().eq('user_id', oldUid);
          removed++;
        } catch (_) {}
      }
    }
    await _loadProfiles();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(removed > 0
            ? 'Removed $removed duplicate profile${removed == 1 ? '' : 's'}'
            : 'No duplicates found'),
      ));
    }
  }

  Widget _profileCard(Map<String, dynamic> p) {
    final uid = p['user_id'] as String? ?? '';
    final name = p['name'] as String? ?? '';
    final callsign = p['callsign'] as String? ?? '';
    final certLevel = p['cert_level'] as String? ?? 'None';
    final rt130 = p['rt130'] as bool? ?? false;
    final ropeRescue = p['rope_rescue'] as bool? ?? false;
    final display = callsign.isNotEmpty ? callsign : name;
    final certColor = _certColor(certLevel);
    final isMe = uid == _myUserId && uid.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: certColor.withValues(alpha: 0.15),
              child: Text(display.isNotEmpty ? display[0].toUpperCase() : '?',
                  style: TextStyle(fontWeight: FontWeight.bold, color: certColor)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(display, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('You',
                        style: TextStyle(fontSize: 10, color: Colors.indigo,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              if (callsign.isNotEmpty && name.isNotEmpty)
                Text(name, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            if (isMe)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit my profile',
                onPressed: () => _editProfile(),
              ),
            if (_isAdmin)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                tooltip: 'Delete profile',
                onPressed: () => _confirmDeleteProfile(uid, display),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: certColor.withValues(alpha: 0.12),
                border: Border.all(color: certColor.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(certLevel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: certColor)),
            ),
            if (rt130)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('RT-130',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
              ),
            if (ropeRescue)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Rope',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue)),
              ),
          ]),
        ]),
      ),
    );
  }

  void _editProfile() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => LoginScreen(
        onLoggedIn: () {
          Navigator.pop(context);
          _loadProfiles(); // refresh so updated data shows immediately
        },
      ),
    ));
  }

  Future<void> _confirmDeleteProfile(String uid, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('Remove $displayName from the team roster? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseService.client!.from('user_profiles').delete().eq('user_id', uid);
      setState(() => _profileRows.removeWhere((r) => r['user_id'] == uid));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName removed from roster.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }


  Widget _memberTile(TeamMember m) {
    final certCol = _certColor(m.certification);
    final statusCol = _memberStatusColor(m.status);
    final expiring = m.isCertExpired || m.isCertExpiringSoon;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Stack(clipBehavior: Clip.none, children: [
          CircleAvatar(
            backgroundColor: certCol.withValues(alpha: 0.15),
            child: Text(
              m.certification.length > 4
                  ? m.certification.substring(0, 3)
                  : m.certification,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: certCol),
            ),
          ),
          Positioned(
            right: -2, bottom: -2,
            child: Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: statusCol, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)),
            ),
          ),
        ]),
        title: Row(children: [
          Expanded(child: Text(m.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          if (m.callsign.isNotEmpty)
            Text(m.callsign, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
        subtitle: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: statusCol.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4)),
            child: Text(m.status,
                style: TextStyle(fontSize: 10, color: statusCol, fontWeight: FontWeight.w600)),
          ),
          if (expiring) ...[
            const SizedBox(width: 6),
            Icon(m.isCertExpired ? Icons.error : Icons.warning_amber, size: 14,
                color: m.isCertExpired ? Colors.red : Colors.orange),
            Text(m.isCertExpired ? ' Expired' : ' Expiring soon',
                style: TextStyle(fontSize: 10,
                    color: m.isCertExpired ? Colors.red : Colors.orange)),
          ],
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _openForm(m)),
          IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              onPressed: () async {
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
  List<String> _assignableNames = []; // roster + Supabase profiles
  bool _loading = true;
  String _filter = 'Active';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final tasks = await TaskStorage.load();
    final members = await RosterStorage.load();
    // Build assignable names: local roster + Supabase user_profiles
    final names = <String>{};
    for (final m in members) { names.add(m.displayName); }
    try {
      final ok = await SupabaseService.ensureInitialized();
      if (ok) {
        final rows = await SupabaseService.client!
            .from('user_profiles')
            .select('name, callsign')
            .order('name') as List;
        for (final r in rows) {
          final name = r['name'] as String? ?? '';
          final cs   = r['callsign'] as String? ?? '';
          if (name.isNotEmpty) names.add(cs.isNotEmpty ? '$name ($cs)' : name);
        }
      }
    } catch (_) {}
    if (mounted) setState(() {
      _tasks = tasks;
      _members = members;
      _assignableNames = names.toList()..sort();
      _loading = false;
    });
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
      builder: (_) => _TaskFormSheet(existing: existing, members: _members, assignableNames: _assignableNames),
    );
    if (result == true) _load();
  }

  void _openTaskDetail(OpTask t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(builder: (ctx, ss) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              // Title + edit button
              Row(children: [
                Expanded(child: Text(t.title.isEmpty ? '(untitled)' : t.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () { Navigator.pop(ctx); _openForm(t); },
                ),
              ]),
              if (t.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(t.description, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ],
              const Divider(height: 24),
              // Priority + assigned
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _priorityColor(t.priority).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _priorityColor(t.priority).withValues(alpha: 0.4)),
                  ),
                  child: Text(t.priority, style: TextStyle(
                      fontSize: 11, color: _priorityColor(t.priority), fontWeight: FontWeight.w600)),
                ),
                if (t.assignedTo.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(t.assignedTo, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ]),
              if (t.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(t.notes, style: const TextStyle(fontSize: 13)),
              ],
              const Divider(height: 24),
              const Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                  color: Colors.grey, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              // Status buttons
              Wrap(spacing: 8, runSpacing: 8, children: _kTaskStatuses.map((s) {
                final selected = t.status == s;
                final col = _taskStatusColor(s);
                return GestureDetector(
                  onTap: () async {
                    t.status = s;
                    await TaskStorage.save(t);
                    ss(() {}); // refresh sheet
                    _load();   // refresh list
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? col : col.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: col.withValues(alpha: selected ? 1 : 0.4),
                          width: selected ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (selected) ...[
                        Icon(Icons.check_circle, size: 14,
                            color: selected ? Colors.white : col),
                        const SizedBox(width: 4),
                      ],
                      Text(s, style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : col)),
                    ]),
                  ),
                );
              }).toList()),
            ],
          ),
        );
      }),
    );
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
                onTap: () => _openTaskDetail(t),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _TaskFormSheet extends StatefulWidget {
  final OpTask? existing;
  final List<TeamMember> members;
  final List<String> assignableNames;
  const _TaskFormSheet({this.existing, required this.members, this.assignableNames = const []});
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
          // Assignee — populated from Supabase user_profiles + local roster
          DropdownButtonFormField<String>(
            value: _assignedTo.isEmpty ? null : _assignedTo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Assigned To',
              border: OutlineInputBorder(), isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Unassigned')),
              ...(() {
                // Merge Supabase names with local roster names (deduplicated)
                final all = <String>{
                  ...widget.assignableNames,
                  ...widget.members.map((m) => m.displayName),
                }.toList()..sort();
                return all.map((name) => DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ));
              })(),
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
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString('tac_callsign') ?? 'Unknown';
    await AdminAlertService.post(
      type: 'handoff',
      title: 'Handoff Submitted',
      callsign: callsign,
      body: h.outgoingLead.isNotEmpty ? 'Outgoing: ${h.outgoingLead}' : '',
    );
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


class _DeploymentOrdersTab extends StatefulWidget {
  const _DeploymentOrdersTab();
  @override
  State<_DeploymentOrdersTab> createState() => _DeploymentOrdersTabState();
}

class _DeploymentOrdersTabState extends State<_DeploymentOrdersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<DeploymentOrder> _orders = [];
  bool _loading = true;
  bool _notConfigured = false;
  bool _isAdmin = false;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final isAdmin = await ProtocolSyncService.instance.isAdminMode;
    if (mounted) setState(() => _isAdmin = isAdmin);
    await _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _notConfigured = false; });
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) {
      if (mounted) setState(() { _loading = false; _notConfigured = true; });
      return;
    }
    final orders = await ProtocolSyncService.instance.allDeploymentOrders();
    if (mounted) setState(() { _orders = orders; _loading = false; });
  }

  Future<void> _viewOrder(DeploymentOrder order) async {
    setState(() => _downloading.add(order.id));

    // Fetch bytes from database (base64) or legacy storage fallback.
    final bytes = await ProtocolSyncService.instance.fetchOrderBytes(order);

    setState(() => _downloading.remove(order.id));
    if (!mounted) return;

    if (bytes == null) {
      _showOrderError(
        'Could not load the file for this order.\n\n'
        'This order was uploaded before the current version.\n'
        'Please ask admin to delete it and re-upload.',
      );
      return;
    }

    final ext = order.fileName.contains('.')
        ? order.fileName.split('.').last.toLowerCase()
        : '';
    final isPdf = ext == 'pdf' || ext.isEmpty;

    try {
      if (isPdf) {
        final magic = bytes.length >= 4
            ? String.fromCharCodes(bytes.sublist(0, 4))
            : '';
        if (!magic.startsWith('%PDF')) {
          _showOrderError(
            'Not a valid PDF (${bytes.length} bytes, header: "$magic").\n'
            'Delete this order and re-upload.',
          );
          return;
        }
        if (!mounted) return;
        // PdfPreview renders via bitmap on Android — more reliable than pdfrx.
        final capturedBytes = bytes;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Text(order.title, style: const TextStyle(fontSize: 15)),
                if (order.notes.isNotEmpty)
                  Text(order.notes, style: const TextStyle(fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            body: PdfPreview(
              build: (_) async => capturedBytes,
              allowSharing: false,
              allowPrinting: false,
              canChangePageFormat: false,
              canDebug: false,
            ),
          ),
        ));
      } else {
        // Image (JPEG, PNG, etc.)
        if (!mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(order.title,
                  style: const TextStyle(fontSize: 15, color: Colors.white)),
            ),
            body: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, err, __) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Image could not be displayed.\n'
                        '${bytes.length} bytes, ext: $ext\n$err',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
      }
      // After viewer closes — prompt acknowledgment.
      if (mounted) {
        final confirmed = await showReadAcknowledgment(
          context,
          title: order.title,
          docType: 'Deployment Order',
        );
        if (confirmed) {
          await ProtocolSyncService.instance.markDeploymentOrderViewed(order.id);
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      if (mounted) _showOrderError('Open failed: $e');
    }
  }

  void _showOrderError(String detail) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Could not open order'),
      content: SingleChildScrollView(child: SelectableText(detail,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ));
  }

  Future<void> _showUploadSheet() async {
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    Uint8List? bytes;
    String? fileName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('New Deployment Order',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes / Instructions', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: Text(fileName ?? 'Attach Document (PDF or image)'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                    withData: true,
                  );
                  if (result == null) return;
                  final f = result.files.first;
                  Uint8List? b = f.bytes;
                  if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
                  setSt(() { bytes = b; fileName = f.name; });
                },
              ),
              if (bytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(fileName ?? '', style: const TextStyle(fontSize: 12, color: Colors.green)),
                ),
              const SizedBox(height: 16),
              _OrderUploadButton(
                titleCtrl: titleCtrl,
                notesCtrl: notesCtrl,
                bytes: bytes,
                fileName: fileName,
                onSuccess: () { Navigator.pop(ctx); _load(); },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notConfigured) return _notConfiguredWidget();
    return Scaffold(
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showUploadSheet,
              icon: const Icon(Icons.upload_file),
              label: const Text('Push Order'))
          : null,
      body: _orders.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No deployment orders yet.', style: TextStyle(color: Colors.grey)),
              if (_isAdmin) ...[
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _showUploadSheet,
                    icon: const Icon(Icons.upload_file), label: const Text('Push First Order')),
              ],
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: _orders.length,
                itemBuilder: (_, i) {
                  final o = _orders[i];
                  final downloading = _downloading.contains(o.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.assignment_outlined, color: Colors.orange, size: 36),
                      title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${o.uploadedBy.isNotEmpty ? 'From: ${o.uploadedBy}  •  ' : ''}${_fmtTc(o.uploadedAt)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (o.notes.isNotEmpty)
                          Text(o.notes, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                      ]),
                      isThreeLine: o.notes.isNotEmpty,
                      trailing: downloading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.open_in_new, size: 20),
                      onTap: downloading ? null : () => _viewOrder(o),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _OrderUploadButton extends StatefulWidget {
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final Uint8List? bytes;
  final String? fileName;
  final VoidCallback onSuccess;
  const _OrderUploadButton({
    required this.titleCtrl,
    required this.notesCtrl,
    required this.bytes,
    required this.fileName,
    required this.onSuccess,
  });
  @override
  State<_OrderUploadButton> createState() => _OrderUploadButtonState();
}

class _OrderUploadButtonState extends State<_OrderUploadButton> {
  bool _uploading = false;

  Future<void> _upload() async {
    if (widget.bytes == null || widget.fileName == null) return;
    final title = widget.titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _uploading = true);
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString('tac_callsign') ?? 'Admin';
    try {
      await ProtocolSyncService.instance.uploadDeploymentOrder(
        title: title,
        notes: widget.notesCtrl.text.trim(),
        bytes: widget.bytes!,
        fileName: widget.fileName!,
        uploadedBy: callsign,
      );
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = widget.bytes != null && !_uploading && widget.titleCtrl.text.trim().isNotEmpty;
    return FilledButton.icon(
      onPressed: canUpload ? _upload : null,
      icon: _uploading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send),
      label: Text(_uploading ? 'Uploading…' : 'Push to Team'),
    );
  }
}


class _AvailabilityTab extends StatefulWidget {
  const _AvailabilityTab();
  @override
  State<_AvailabilityTab> createState() => _AvailabilityTabState();
}

class _AvailabilityTabState extends State<_AvailabilityTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _loading = true;
  bool _notConfigured = false;
  DateTime _displayMonth = DateTime.now();
  final Map<String, List<Map<String, String>>> _dayEntries = {};
  String _myUserId = '';
  String _myCallsign = '';

  // Range selection
  bool _rangeMode = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  static const _statuses = ['Available', 'Unavailable', 'Partial', 'Deployed'];
  static const Map<String, Color> _statusColors = {
    'Available': Color(0xFF2E7D32),
    'Unavailable': Color(0xFFC62828),
    'Partial': Color(0xFFE65100),
    'Deployed': Color(0xFF1565C0),
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getString('tac_user_id') ?? '';
    _myCallsign = prefs.getString('tac_callsign') ?? 'Me';
    if (_myUserId.isEmpty) {
      final rng = Random.secure();
      _myUserId = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString('tac_user_id', _myUserId);
    }
    await _cleanCalendar();
    await _load();
  }

  /// Removes orphaned calendar entries (user_id no longer present in
  /// user_profiles — e.g. the profile was deleted). Does NOT attempt to
  /// dedupe by callsign/name: that used to pick a "canonical" user_id and
  /// delete every other matching row, which meant two people who happened
  /// to share a callsign/name would have one of their live availability
  /// entries silently wiped on every calendar load. Duplicate callsigns are
  /// now rejected at profile creation instead (see UserProfile.callsignTaken).
  Future<void> _cleanCalendar() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) return;
    final client = SupabaseService.client!;
    try {
      final profiles = await client
          .from('user_profiles')
          .select('user_id') as List;
      if (profiles.isEmpty) return; // safety — don't wipe calendar if profiles table is empty
      final validIds = profiles.map((p) => p['user_id'] as String).toSet();

      final avail = await client
          .from('team_availability')
          .select('user_id') as List;
      final seenUids = avail.map((r) => r['user_id'] as String).toSet();

      final orphaned = seenUids.where((uid) => !validIds.contains(uid)).toList();
      for (final uid in orphaned) {
        await client.from('team_availability').delete().eq('user_id', uid);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _notConfigured = false; });
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) {
      if (mounted) setState(() { _loading = false; _notConfigured = true; });
      return;
    }
    try {
      final client = SupabaseService.client!;
      final start = DateTime(_displayMonth.year, _displayMonth.month, 1);
      final end = DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
      final rows = (await client
              .from('team_availability')
              .select()
              .gte('date', '${start.year}-${_pad(start.month)}-01')
              .lte('date', '${end.year}-${_pad(end.month)}-${_pad(end.day)}')
              .order('date') as List)
          .cast<Map<String, dynamic>>();
      final Map<String, List<Map<String, String>>> entries = {};
      for (final r in rows) {
        final date = r['date'] as String;
        entries.putIfAbsent(date, () => []).add({
          'user_id': r['user_id'] as String,
          'callsign': r['callsign'] as String? ?? '',
          'status': r['status'] as String? ?? 'Available',
          'notes': r['notes'] as String? ?? '',
        });
      }
      if (mounted) {
        setState(() {
          _dayEntries..clear()..addAll(entries);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showDaySheet(String dateStr, bool isPast) async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    final entries = List<Map<String, String>>.from(_dayEntries[dateStr] ?? []);
    final myEntry = entries.where((e) => e['user_id'] == _myUserId).firstOrNull;

    final parts = dateStr.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label = '${dayNames[dt.weekday - 1]}, ${monthNames[dt.month]} ${dt.day}';

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16, right: 16, top: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No availability set for this day.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            )
          else
            ...entries.map((e) {
              final color = _statusColors[e['status']] ?? Colors.grey;
              final isMe = e['user_id'] == _myUserId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                    child: Text(e['status']!,
                        style: const TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Text(isMe ? '${e['callsign']} (me)' : e['callsign']!,
                      style: TextStyle(
                          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14)),
                  if ((e['notes'] ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(child: Text(e['notes']!,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                  ],
                ]),
              );
            }),
          if (!isPast) ...[
            const Divider(height: 24),
            Text('Set your status:',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700],
                    fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _statuses.map((s) {
                final selected = myEntry?['status'] == s;
                final color = _statusColors[s]!;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveStatus(dateStr, s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? color : color.withValues(alpha: 0.10),
                      border: Border.all(color: color, width: 1.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(s, style: TextStyle(
                        color: selected ? Colors.white : color,
                        fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                );
              }).toList(),
            ),
            if (myEntry != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveStatus(dateStr, 'remove');
                },
                child: Text('Clear my status',
                    style: TextStyle(color: Colors.red[400], fontSize: 13)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }

  void _onDayTap(DateTime date, String dateStr, bool isPast) {
    if (!_rangeMode) {
      _showDaySheet(dateStr, isPast);
      return;
    }
    if (_rangeStart == null || _rangeEnd != null) {
      setState(() { _rangeStart = date; _rangeEnd = null; });
    } else {
      final start = date.isBefore(_rangeStart!) ? date : _rangeStart!;
      final end   = date.isBefore(_rangeStart!) ? _rangeStart! : date;
      setState(() { _rangeStart = start; _rangeEnd = end; });
      _showRangeSheet(start, end);
    }
  }

  Future<void> _showRangeSheet(DateTime start, DateTime end) async {
    const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label =
        '${monthNames[start.month]} ${start.day} – ${monthNames[end.month]} ${end.day}, ${end.year}';
    final days = end.difference(start).inDays + 1;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16, right: 16, top: 12),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text('$days day${days == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 14),
          Text('Set your status for the entire range:',
              style: TextStyle(fontWeight: FontWeight.w600,
                  color: Colors.grey[700], fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _statuses.map((s) {
              final color = _statusColors[s]!;
              return GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await _saveRangeStatus(start, end, s);
                  if (mounted) {
                    setState(() { _rangeMode = false; _rangeStart = null; _rangeEnd = null; });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    border: Border.all(color: color, width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(s, style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (mounted) setState(() { _rangeStart = null; _rangeEnd = null; });
                },
                child: const Text('Cancel'),
              ),
            ),
          ]),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  Future<void> _saveRangeStatus(DateTime start, DateTime end, String status) async {
    final client = SupabaseService.client;
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Supabase not connected — open Tac Map to configure.'),
            backgroundColor: Colors.orange));
      }
      return;
    }
    try {
      final rows = <Map<String, dynamic>>[];
      for (var d = start;
          !d.isAfter(end);
          d = d.add(const Duration(days: 1))) {
        rows.add({
          'user_id': _myUserId,
          'callsign': _myCallsign,
          'date': '${d.year}-${_pad(d.month)}-${_pad(d.day)}',
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      await client.from('team_availability').upsert(rows, onConflict: 'user_id,date');
      await AdminAlertService.post(
        type: 'availability',
        title: 'Availability Updated',
        callsign: _myCallsign,
        body: '$status — ${rows.length}-day range',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error saving range: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveStatus(String dateStr, String status) async {
    final client = SupabaseService.client;
    if (client == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Supabase not connected — open Tac Map to configure.'),
            backgroundColor: Colors.orange));
      }
      return;
    }
    try {
      if (status == 'remove') {
        await client.from('team_availability')
            .delete().eq('user_id', _myUserId).eq('date', dateStr);
      } else {
        await client.from('team_availability').upsert({
          'user_id': _myUserId,
          'callsign': _myCallsign,
          'date': dateStr,
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,date');
        await AdminAlertService.post(
          type: 'availability',
          title: 'Availability Updated',
          callsign: _myCallsign,
          body: '$status on $dateStr',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error saving: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_notConfigured) return _notConfiguredWidget();

    final now = DateTime.now();
    final firstDay = DateTime(_displayMonth.year, _displayMonth.month, 1);
    final daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;
    final numWeeks = ((startWeekday + daysInMonth) / 7).ceil();

    return Column(children: [
      Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() => _displayMonth =
                DateTime(_displayMonth.year, _displayMonth.month - 1));
            _load();
          },
        ),
        Expanded(
          child: Text(_monthLabel(_displayMonth),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        IconButton(
          icon: const Icon(Icons.today),
          tooltip: 'Today',
          onPressed: () {
            setState(() => _displayMonth = DateTime.now());
            _load();
          },
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() => _displayMonth =
                DateTime(_displayMonth.year, _displayMonth.month + 1));
            _load();
          },
        ),
        TextButton.icon(
          icon: Icon(
            _rangeMode ? Icons.close : Icons.date_range,
            size: 16,
          ),
          label: Text(_rangeMode ? 'Cancel' : 'Range',
              style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: _rangeMode
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => setState(() {
            _rangeMode = !_rangeMode;
            _rangeStart = null;
            _rangeEnd = null;
          }),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'].map((d) =>
            Expanded(child: Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ).toList(),
        ),
      ),
      const Divider(height: 6),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: List.generate(numWeeks, (week) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(7, (col) {
                    final idx = week * 7 + col;
                    final dayNum = idx - startWeekday + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 64));
                    }
                    final date =
                        DateTime(_displayMonth.year, _displayMonth.month, dayNum);
                    final dateStr =
                        '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
                    final entries = _dayEntries[dateStr] ?? [];
                    final myEntry = entries
                        .where((e) => e['user_id'] == _myUserId)
                        .firstOrNull;
                    final isToday = date.year == now.year &&
                        date.month == now.month &&
                        date.day == now.day;
                    final isPast = date.isBefore(
                        DateTime(now.year, now.month, now.day));
                    final inRange = _rangeMode &&
                        _rangeStart != null &&
                        _rangeEnd != null &&
                        !date.isBefore(_rangeStart!) &&
                        !date.isAfter(_rangeEnd!);
                    final isRangeEdge = _rangeMode &&
                        _rangeStart != null &&
                        (date == _rangeStart ||
                            (_rangeEnd != null && date == _rangeEnd));

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _onDayTap(date, dateStr, isPast),
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          constraints: const BoxConstraints(minHeight: 64),
                          decoration: BoxDecoration(
                            color: inRange
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15)
                                : myEntry != null
                                    ? (_statusColors[myEntry['status']] ??
                                            Colors.grey)
                                        .withValues(alpha: 0.10)
                                    : null,
                            border: Border.all(
                              color: isRangeEdge || isToday
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.withValues(alpha: 0.2),
                              width: isRangeEdge || isToday ? 2 : 0.5,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(3, 2, 2, 1),
                                child: Text('$dayNum',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isToday
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isToday
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : isPast
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.35)
                                              : null,
                                    )),
                              ),
                              ...entries.map((e) {
                                final color =
                                    _statusColors[e['status']] ?? Colors.grey;
                                final name = (e['callsign']?.isNotEmpty == true)
                                    ? e['callsign']!
                                    : e['status']!;
                                return Container(
                                  margin: const EdgeInsets.only(
                                      left: 1, right: 1, bottom: 1),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 2, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                        alpha: isPast ? 0.45 : 0.90),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            ..._statusColors.entries.map((e) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: e.value, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(e.key, style: const TextStyle(fontSize: 11)),
              ],
            )),
            Text(
              _rangeMode
                  ? (_rangeStart == null
                      ? 'Tap a start date'
                      : 'Tap an end date')
                  : 'Tap a day to set status  •  Tap "Range" to set multiple days at once',
              style: TextStyle(fontSize: 10, color: _rangeMode
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[500]),
            ),
          ],
        ),
      ),
    ]);
  }

  static String _monthLabel(DateTime d) {
    const names = ['', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'];
    return '${names[d.month]} ${d.year}';
  }
}


Widget _notConfiguredWidget() => const Center(
  child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.cloud_off, size: 64, color: Colors.grey),
    SizedBox(height: 16),
    Text('Supabase not configured', style: TextStyle(fontSize: 16)),
    SizedBox(height: 8),
    Text('Open Tac Map to connect to your Supabase project.',
        style: TextStyle(color: Colors.grey, fontSize: 13)),
  ]),
);

String _fmtTc(DateTime dt) =>
    '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';

String _pad(int n) => n.toString().padLeft(2, '0');


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
