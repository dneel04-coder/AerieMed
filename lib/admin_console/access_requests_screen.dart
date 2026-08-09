import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../protocol_admin.dart' show SupabaseService;

/// Review self-serve "request access" submissions ahead of the mobile app's
/// paywall — approving/denying here is what actually lets (or doesn't let)
/// someone reach the purchase flow; see access_requests schema/triggers.
class AccessRequestsScreen extends StatefulWidget {
  const AccessRequestsScreen({super.key});

  @override
  State<AccessRequestsScreen> createState() => _AccessRequestsScreenState();
}

class _AccessRequestsScreenState extends State<AccessRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    try {
      final rows = await SupabaseService.client!
          .from('access_requests')
          .select()
          .order('requested_at', ascending: false);
      if (mounted) setState(() { _requests = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _subscribe() {
    final client = SupabaseService.client;
    if (client == null) return;
    _channel = client
        .channel('admin_console_access_requests')
        .onPostgresChanges(
            event: PostgresChangeEvent.all, schema: 'public', table: 'access_requests',
            callback: (_) => _load())
        .subscribe();
  }

  Future<void> _decide(Map<String, dynamic> row, String status) async {
    try {
      await SupabaseService.client!.from('access_requests').update({
        'status': status,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
        'decided_by': 'Command Console',
      }).eq('id', row['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final pending = _requests.where((r) => r['status'] == 'pending').toList();
    final decided = _requests.where((r) => r['status'] != 'pending').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pending (${pending.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No pending requests', style: TextStyle(color: Colors.grey)),
            ),
          ...pending.map((r) => _RequestCard(row: r, onDecide: _decide)),
          if (decided.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Decided', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...decided.map((r) => _RequestCard(row: r, onDecide: _decide)),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final void Function(Map<String, dynamic> row, String status) onDecide;
  const _RequestCard({required this.row, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String? ?? 'pending';
    final name = row['name'] as String? ?? '';
    final callsign = row['callsign'] as String? ?? '';
    final company = row['company'] as String? ?? '';
    final email = row['email'] as String? ?? '';
    final statusColor = switch (status) {
      'approved' => Colors.green,
      'denied' => Colors.red,
      _ => Colors.orange,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ]),
              if (callsign.isNotEmpty || company.isNotEmpty)
                Text([if (callsign.isNotEmpty) callsign, if (company.isNotEmpty) company].join(' · '),
                    style: TextStyle(color: Colors.grey[600])),
              if (email.isNotEmpty) Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
          if (status == 'pending') ...[
            OutlinedButton(
              onPressed: () => onDecide(row, 'denied'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Deny'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => onDecide(row, 'approved'), child: const Text('Approve')),
          ],
        ]),
      ),
    );
  }
}
