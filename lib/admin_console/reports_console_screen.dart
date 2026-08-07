import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;
import '../patient_report.dart' show PatientReport;
import '../report_pdf.dart';
import '../tac_map.dart' show TacUser;
import '../incident_service.dart';

enum _ReportsMode { allReports, thisIncident }

class _ReportRow {
  final String userId;
  final String callsign;
  final DateTime submittedAt;
  final PatientReport report;
  const _ReportRow({required this.userId, required this.callsign, required this.submittedAt, required this.report});
}

/// Patient reports, either every one ever submitted or scoped to the active
/// incident via incident_members.user_id (see IncidentService) — no
/// patient_reports schema change or mobile-side touch required either way.
class ReportsConsoleScreen extends StatefulWidget {
  final TacIncident? incident;
  const ReportsConsoleScreen({super.key, required this.incident});

  @override
  State<ReportsConsoleScreen> createState() => _ReportsConsoleScreenState();
}

class _ReportsConsoleScreenState extends State<ReportsConsoleScreen> {
  List<_ReportRow> _allReports = [];
  List<_ReportRow> _attached = [];
  List<_ReportRow> _unattached = [];
  _ReportRow? _selected;
  bool _loading = true;
  late _ReportsMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.incident == null ? _ReportsMode.allReports : _ReportsMode.thisIncident;
    _load();
  }

  @override
  void didUpdateWidget(covariant ReportsConsoleScreen old) {
    super.didUpdateWidget(old);
    if (old.incident?.id != widget.incident?.id) {
      if (widget.incident == null) _mode = _ReportsMode.allReports;
      _load();
    }
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
    setState(() { _loading = true; _selected = null; });

    final client = SupabaseService.client;
    var allReports = <_ReportRow>[];
    var attached = <_ReportRow>[];
    var unattached = <_ReportRow>[];

    if (client != null) {
      try {
        final rows = await client
            .from('patient_reports')
            .select()
            .order('submitted_at', ascending: false) as List;
        allReports = rows.map((r) => _parseRow(r as Map<String, dynamic>)).whereType<_ReportRow>().toList();
      } catch (_) {}

      final incident = widget.incident;
      if (incident != null) {
        try {
          final members = await IncidentService.instance.fetchMembers(incident.id);
          final memberIds = members.where((m) => m.isActive).map((m) => m.userId).toSet();
          attached = allReports.where((r) => memberIds.contains(r.userId)).toList();

          // Reports from users currently online on this mission code but not
          // yet added to the incident roster — likely belong here, admin can
          // add them from the Roster screen.
          final onlineRows = await client
              .from('tac_users')
              .select()
              .eq('mission_code', incident.missionCode) as List;
          final online = onlineRows.map((r) => TacUser.fromMap(r as Map<String, dynamic>)).toList();
          final onlineIds = online.map((u) => u.id).where((id) => !memberIds.contains(id)).toSet();
          unattached = allReports.where((r) => onlineIds.contains(r.userId)).toList();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _allReports = allReports;
        _attached = attached;
        _unattached = unattached;
        _loading = false;
      });
    }
  }

  Future<void> _downloadPdf(_ReportRow row) async {
    try {
      final bytes = await buildReportPdf(row.report);
      final defaultName =
          'ResQruck_${row.report.patientId.isEmpty ? row.report.id : row.report.patientId.replaceAll(' ', '_')}.pdf';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Patient Report PDF',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savePath == null) return;
      final path = savePath.toLowerCase().endsWith('.pdf') ? savePath : '$savePath.pdf';
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save PDF: $e')));
      }
    }
  }

  Future<void> _deleteReport(_ReportRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report?'),
        content: Text('Permanently remove the ${row.report.formType} report for '
            '${row.report.patientId.isEmpty ? row.callsign : row.report.patientId}? This cannot be undone.'),
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
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('patient_reports').delete().eq('id', row.report.id);
      if (mounted) setState(() => _selected = null);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete report: $e')));
      }
    }
  }

  Future<void> _attach(_ReportRow row) async {
    final incident = widget.incident;
    if (incident == null) return;
    try {
      await IncidentService.instance.addMember(incident.id, userId: row.userId, callsign: row.callsign);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not attach report: $e')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<_ReportsMode>(
          segments: const [
            ButtonSegment(value: _ReportsMode.allReports, label: Text('All Reports'), icon: Icon(Icons.list_alt)),
            ButtonSegment(
                value: _ReportsMode.thisIncident,
                label: Text('This Incident'),
                icon: Icon(Icons.local_fire_department)),
          ],
          selected: {_mode},
          onSelectionChanged: widget.incident == null ? null : (s) => setState(() => _mode = s.first),
        ),
      ),
      Expanded(
        child: Row(children: [
          SizedBox(
            width: 340,
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: _mode == _ReportsMode.allReports ? _buildAllReportsList() : _buildThisIncidentList(),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selected == null
                ? const Center(child: Text('Select a report to view'))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            '${_selected!.report.formType} — '
                            '${_selected!.report.patientId.isEmpty ? _selected!.callsign : _selected!.report.patientId}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _downloadPdf(_selected!),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download PDF'),
                        ),
                        TextButton.icon(
                          onPressed: () => _deleteReport(_selected!),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          label: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ]),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SelectableText(_selected!.report.formattedText,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    ]);
  }

  List<Widget> _buildAllReportsList() {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Text('All reports (${_allReports.length})', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ]),
      ),
      if (_allReports.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No reports submitted yet.', style: TextStyle(color: Colors.grey[600])),
        ),
      ..._allReports.map((r) => Card(
            color: _selected == r ? Theme.of(context).colorScheme.primaryContainer : null,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.assignment_outlined),
              title: Text(r.callsign),
              subtitle: Text('${r.report.formType} • ${_fmt(r.submittedAt)}'),
              onTap: () => setState(() => _selected = r),
            ),
          )),
    ];
  }

  List<Widget> _buildThisIncidentList() {
    return [
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
    ];
  }

  String _fmt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
