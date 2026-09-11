import 'package:flutter/material.dart';
import 'form_outbox_service.dart';
import 'crew_swap_form.dart' show CrewSwapFormScreen;
import 'shift_ticket_form.dart' show ShiftTicketFormScreen;
import 'sf261_form.dart' show Sf261FormScreen;
import 'ics214_form.dart' show Ics214FormScreen;
import 'ics205_form.dart' show Ics205FormScreen;
import 'ics213_form.dart' show Ics213FormScreen;

class _FormEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  const _FormEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
  });
}

final List<_FormEntry> _kForms = [
  const _FormEntry(
    title: 'Shift Ticket',
    subtitle: 'OF-297 — Emergency Equipment Shift Ticket',
    icon: Icons.receipt_long_outlined,
    color: Colors.brown,
    builder: _buildShiftTicket,
  ),
  const _FormEntry(
    title: 'Crew Swap',
    subtitle: 'CIMT 2 Crew Change Form',
    icon: Icons.swap_horiz,
    color: Colors.deepPurple,
    builder: _buildCrewSwap,
  ),
  const _FormEntry(
    title: 'Activity Log',
    subtitle: 'ICS 214',
    icon: Icons.history_edu_outlined,
    color: Colors.teal,
    builder: _buildIcs214,
  ),
  const _FormEntry(
    title: 'Incident Radio Communications Plan',
    subtitle: 'ICS 205',
    icon: Icons.radio_outlined,
    color: Colors.indigo,
    builder: _buildIcs205,
  ),
  const _FormEntry(
    title: 'General Message',
    subtitle: 'ICS 213',
    icon: Icons.mail_outline,
    color: Colors.blueGrey,
    builder: _buildIcs213,
  ),
  const _FormEntry(
    title: 'Crew Time Report',
    subtitle: 'SF-261',
    icon: Icons.groups_outlined,
    color: Colors.orange,
    builder: _buildSf261,
  ),
];

Widget _buildShiftTicket(BuildContext context) => const ShiftTicketFormScreen();
Widget _buildCrewSwap(BuildContext context) => const CrewSwapFormScreen();
Widget _buildIcs214(BuildContext context) => const Ics214FormScreen();
Widget _buildIcs205(BuildContext context) => const Ics205FormScreen();
Widget _buildIcs213(BuildContext context) => const Ics213FormScreen();
Widget _buildSf261(BuildContext context) => const Sf261FormScreen();

/// Central hub for every fillable, signable, shareable form in the app --
/// each of these screens is designed to be embedded (no Scaffold/AppBar of
/// its own, matching how they're also used as Team Command tabs), so this
/// hub wraps whichever one is tapped in its own Scaffold for standalone
/// navigation.
class FormsHubScreen extends StatelessWidget {
  const FormsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forms')),
      body: Column(children: [
        ValueListenableBuilder<int>(
          valueListenable: FormOutboxService.instance.pendingCount,
          builder: (context, pending, _) {
            if (pending == 0) return const SizedBox.shrink();
            return Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.cloud_off, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending == 1
                        ? '1 form queued — will send automatically once connected'
                        : '$pending forms queued — will send automatically once connected',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => FormOutboxService.instance.flushQueue(),
                  child: const Text('Retry now'),
                ),
              ]),
            );
          },
        ),
        Expanded(
          child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _kForms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = _kForms[index];
          return Card(
            elevation: 2,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: entry.color.withValues(alpha: 0.15),
                child: Icon(entry.icon, color: entry.color),
              ),
              title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(entry.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => Scaffold(
                    appBar: AppBar(title: Text(entry.title)),
                    body: entry.builder(ctx),
                  ),
                ),
              ),
            ),
          );
        },
          ),
        ),
      ]),
    );
  }
}
