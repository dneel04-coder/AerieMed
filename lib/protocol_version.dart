import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService, ProtocolSyncService, ProtocolEntry;


class VersionEntry {
  final String version;
  final String date;
  final String summary;
  final List<String> changes;
  const VersionEntry({
    required this.version,
    required this.date,
    required this.summary,
    required this.changes,
  });
}


const String kCurrentVersion = '1.3.0';
const String kReleaseDate = '2026-05-26';

const List<VersionEntry> kVersionHistory = [
  VersionEntry(
    version: '1.3.0',
    date: '2026-05-26',
    summary: 'Added clinical decision support tools',
    changes: [
      'NEW: Decision Trees — 5 interactive guided assessments (MARCH, Airway, Shock, AMS, Anaphylaxis)',
      'NEW: Drug Reference — 14 drug cards with full dosing, contraindications, and field notes',
      'NEW: Procedure Checklists — 8 interactive step-by-step checklists with critical step flags',
      'NEW: Differential Diagnosis — 11 conditions organized by category with pitfall alerts',
      'NEW: Dosing Calculator — weight-based offline calculator with Broselow pediatric estimator',
      'NEW: Protocol Version screen — version history with changelog',
      'IMPROVEMENT: Drawer navigation added for all features',
      'FIX: Improved search across all protocols',
    ],
  ),
  VersionEntry(
    version: '1.2.0',
    date: '2026-04-10',
    summary: 'Patient report system and PDF upload',
    changes: [
      'NEW: Patient Report / MIST — fillable field patient report forms',
      'NEW: User PDF upload — import custom protocols into the app',
      'NEW: Favorites — star any protocol for quick access',
      'IMPROVEMENT: Protocols now organized under ABCDE / MARCH categories',
      'FIX: PDF viewer performance improvement on large documents',
    ],
  ),
  VersionEntry(
    version: '1.1.0',
    date: '2026-02-15',
    summary: 'Medication database and appendix material',
    changes: [
      'NEW: Medication folder — 34 medication PDFs organized by category',
      'NEW: Appendix material — GCS, APGAR, pediatric vitals, sedation scores',
      'NEW: ABC quick-access folders — Airway, Breathing, Circulation',
      'NEW: Dark mode support',
      'IMPROVEMENT: Search now covers all protocols and medications simultaneously',
    ],
  ),
  VersionEntry(
    version: '1.0.0',
    date: '2025-12-01',
    summary: 'Initial release',
    changes: [
      'Initial release with 60+ protocol PDFs',
      'Protocol categories: Airway, Breathing, Circulation, Trauma, Other',
      'Expanded scope protocols for aeromedical operations',
      'Altitude illness protocols (AMS, HACE, HAPE)',
      'TCCC / austere environment guidelines',
    ],
  ),
];


class ProtocolVersionScreen extends StatefulWidget {
  const ProtocolVersionScreen({super.key});

  @override
  State<ProtocolVersionScreen> createState() => _ProtocolVersionScreenState();
}

class _ProtocolVersionScreenState extends State<ProtocolVersionScreen> {
  // Protocol log state
  List<ProtocolEntry> _protocols = [];
  Map<String, DateTime?> _ackDates = {}; // protocolId → acknowledged_at
  String _myUserId = '';
  bool _logLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProtocolLog();
  }

  Future<void> _loadProtocolLog() async {
    setState(() => _logLoading = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) { if (mounted) setState(() => _logLoading = false); return; }
    try {
      final client = SupabaseService.client!;
      final prefs = await SharedPreferences.getInstance();
      _myUserId = prefs.getString('tac_user_id') ?? '';
      final protocols = await ProtocolSyncService.instance.allProtocols();
      final acks = await client
          .from('protocol_acknowledgments')
          .select('protocol_id, acknowledged_at')
          .eq('user_id', _myUserId) as List;
      final ackMap = <String, DateTime?>{};
      for (final a in acks) {
        final dt = DateTime.tryParse(a['acknowledged_at'] as String? ?? '');
        ackMap[a['protocol_id'] as String] = dt;
      }
      if (mounted) setState(() {
        _protocols = protocols;
        _ackDates = ackMap;
        _logLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _logLoading = false);
    }
  }

  Future<void> _acknowledge(ProtocolEntry p) async {
    await ProtocolSyncService.instance.acknowledgeProtocol(p.id);
    setState(() => _ackDates[p.id] = DateTime.now());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p.name} acknowledged')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Protocol Version'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.history, size: 18), text: 'App Changelog'),
            Tab(icon: Icon(Icons.verified_user_outlined, size: 18), text: 'Protocol Log'),
          ]),
        ),
        body: TabBarView(children: [
          _buildChangelog(),
          _buildProtocolLog(),
        ]),
      ),
    );
  }

  Widget _buildChangelog() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.verified, size: 28),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CURRENT VERSION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  Text('v$kCurrentVersion', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                ]),
              ]),
              const SizedBox(height: 8),
              Text('Released: $kReleaseDate', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text(kVersionHistory.first.summary, style: const TextStyle(fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Text('Changelog', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...kVersionHistory.map((e) => _VersionCard(entry: e, isCurrent: e.version == kCurrentVersion)),
      ],
    );
  }

  Widget _buildProtocolLog() {
    if (_logLoading) return const Center(child: CircularProgressIndicator());
    if (_protocols.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        const Text('No admin-pushed protocols yet', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          onPressed: _loadProtocolLog,
        ),
      ]));
    }
    final unacked = _protocols.where((p) => !_ackDates.containsKey(p.id)).length;
    return RefreshIndicator(
      onRefresh: _loadProtocolLog,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (unacked > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  '$unacked protocol${unacked == 1 ? '' : 's'} require your acknowledgment',
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ..._protocols.map((p) {
            final ackDate = _ackDates[p.id];
            final acked = ackDate != null;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(acked ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: acked ? Colors.green : Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('v${p.version}',
                          style: const TextStyle(fontSize: 11, color: Colors.indigo,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.upload_outlined, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('Updated ${_fmt(p.updatedAt)} by ${p.updatedBy.isEmpty ? 'Admin' : p.updatedBy}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                  if (p.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.notes, style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  if (acked)
                    Row(children: [
                      const Icon(Icons.verified_outlined, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('You acknowledged this on ${_fmt(ackDate)}',
                          style: const TextStyle(fontSize: 12, color: Colors.green,
                              fontWeight: FontWeight.w600)),
                    ])
                  else
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12)),
                      onPressed: () => _acknowledge(p),
                      child: const Text('Acknowledge this protocol'),
                    ),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _VersionCard extends StatelessWidget {
  final VersionEntry entry;
  final bool isCurrent;
  const _VersionCard({required this.entry, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: isCurrent,
        leading: CircleAvatar(
          backgroundColor: isCurrent
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: isCurrent
              ? Theme.of(context).colorScheme.onPrimary
              : null,
          child: Text('v${entry.version.split('.').first}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        title: Row(children: [
          Text('v${entry.version}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        subtitle: Text('${entry.date} — ${entry.summary}', style: const TextStyle(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entry.changes.map((change) {
                final isNew = change.startsWith('NEW:');
                final isFix = change.startsWith('FIX:');
                final isImprovement = change.startsWith('IMPROVEMENT:');
                Color badgeColor = Colors.grey;
                if (isNew) badgeColor = Colors.green;
                if (isFix) badgeColor = Colors.orange;
                if (isImprovement) badgeColor = Colors.blue;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 8),
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                    ),
                    Expanded(child: Text(change, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
