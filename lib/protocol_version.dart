import 'package:flutter/material.dart';


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


class ProtocolVersionScreen extends StatelessWidget {
  const ProtocolVersionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protocol Version')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current version card
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

          // Version history
          ...kVersionHistory.map((entry) => _VersionCard(entry: entry, isCurrent: entry.version == kCurrentVersion)),
        ],
      ),
    );
  }
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
