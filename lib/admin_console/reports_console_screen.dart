import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../patient_report.dart' show PatientReport;
import '../tac_map.dart' show TacUser;
import 'incident_service.dart';
import 'no_incident_placeholder.dart';

class _ReportRow {
  final String userId;
  final String callsign;
  final DateTime submittedAt;
  final PatientReport report;
  const _ReportRow({required this.userId, required this.callsign, required this.submittedAt, required this.report});
}

/// Reports submitted by field users, scoped to the active incident via
/// incident_members.user_id (see IncidentService) — no patient_reports
/// schema change or mobile-side touch required.
class ReportsConsoleScreen extends StatefulWidget {
  final TacIncident? incident;
  const ReportsConsoleScreen({super.key, required this.incident});

  @override
  State<ReportsConsoleScreen> createState() => _ReportsConsoleScreenState();
}

class _ReportsConsoleScreenState extends State<ReportsConsoleScreen> {
  List<_ReportRow> _attached = [];
  List<_ReportRow> _unattached = [];
  _ReportRow? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReportsConsoleScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.id != widget.incident?.id) _load();
  }

  _ReportRow? _parseRow(Map<String, dynamic> r) {
    try {
      final report = PatientReport.fromJson(r['report_data'] as Map<String, dynamic>);
      return _ReportRow(
        userId: r['user_id'] as String? ?? '',
        callsign: r['callsign'] as String? ?? 'Unknown',
        submittedAt: DateTime.tryParse(r['submitted_at'] as String? ?? '') ?? DateTime.now(),
        report: report,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final incident = widget.incident;
    if (incident == null) return;
    setState(() { _loading = true; _selected = null; });

    final client = SupabaseService.client;
    var attached = <_ReportRow>[];
    var unattached = <_ReportRow>[];

    if (client != null) {
      try {
        final members = await IncidentService.instance.fetchMembers(incident.id);
        final memberIds = members.where((m) => m.isActive).map((m) => m.userId).toList();

        if (memberIds.isNotEmpty) {
          final rows = await client
              .from('patient_reports')
              .select()
              .inFilter('user_id', memberIds)
              .order('submitted_at', ascending: false) as List;
          attached = rows
              .map((r) => _parseRow(r as Map<String, dynamic>))
              .whereType<_ReportRow>()
              .toList();
        }

        // Reports from users currently online on this mission code but not
        // yet added to the incident roster — likely belong here, admin can
        // add them from the Roster screen.
        final onlineRows = await client
            .from('tac_users')
            .select()
            .eq('mission_code', incident.missionCode) as List;
        final online = onlineRows.map((r) => TacUser.fromMap(r as Map<String, dynamic>)).toList();
        final onlineIds = online.map((u) => u.id).where((id) => !memberIds.contains(id)).toList();
        if (onlineIds.isNotEmpty) {
          final rows = await client
              .from('patient_reports')
              .select()
              .inFilter('user_id', onlineIds)
              .order('submitted_at', ascending: false) as List;
          unattached = rows
              .map((r) => _parseRow(r as Map<String, dynamic>))
              .whereType<_ReportRow>()
              .toList();
        }
      } catch (_) {}
    }

    if (mounted) setState(() { _attached = attached; _unattached = unattached; _loading = false; });
  }

  Future<void> _attach(_ReportRow row) async {
    final incident = widget.incident;
    if (incident == null) return;
    await IncidentService.instance.addMember(incident.id, userId: row.userId, callsign: row.callsign);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incident == null) {
      return const NoIncidentPlaceholder(feature: 'Reports');
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Row(children: [
      SizedBox(
        width: 340,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Text('Reports (${_attached.length})', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
              ]),
            ),
            if (_attached.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No reports yet for this incident.', style: TextStyle(color: Colors.grey[600])),
              ),
            ..._attached.map((r) => Card(
                  color: _selected == r ? Theme.of(context).colorScheme.primaryContainer : null,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text(r.callsign),
                    subtitle: Text('${r.report.formType} • ${_fmt(r.submittedAt)}'),
                    onTap: () => setState(() => _selected = r),
                  ),
                )),
            if (_unattached.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Unattached — online on this mission (${_unattached.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              ..._unattached.map((r) => Card(
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.help_outline),
                      title: Text(r.callsign),
                      subtitle: Text('${r.report.formType} • ${_fmt(r.submittedAt)}'),
                      trailing: TextButton(onPressed: () => _attach(r), child: const Text('Attach')),
                      onTap: () => setState(() => _selected = r),
                    ),
                  )),
            ],
          ],
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: _selected == null
            ? const Center(child: Text('Select a report to view'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: SelectableText(_selected!.report.formattedText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              ),
      ),
    ]);
  }

  String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
