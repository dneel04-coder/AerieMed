import 'dart:math';
import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;

class _Org {
  final String id;
  final String name;
  final bool isDefault;
  const _Org({required this.id, required this.name, required this.isDefault});
}

class _JoinCode {
  final String id;
  final String code;
  final bool isActive;
  const _JoinCode({required this.id, required this.code, required this.isActive});
}

class _RosterUser {
  final String userId;
  final String display;
  final String role;
  final String? orgId;
  const _RosterUser({required this.userId, required this.display, required this.role, this.orgId});
}

const _kCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0, I/1 -- avoids transcription errors

String _generateJoinCode() {
  final rng = Random.secure();
  return List.generate(8, (_) => _kCodeAlphabet[rng.nextInt(_kCodeAlphabet.length)]).join();
}

/// Super-admin-only: create organizations, generate/revoke their join
/// codes, and assign roster members as org_admin for a specific org. This
/// is the manual-assignment workflow the org-scoping plan calls for --
/// there is no self-service "first signup becomes admin" path anywhere.
class OrgManagementScreen extends StatefulWidget {
  const OrgManagementScreen({super.key});

  @override
  State<OrgManagementScreen> createState() => _OrgManagementScreenState();
}

class _OrgManagementScreenState extends State<OrgManagementScreen> {
  List<_Org> _orgs = [];
  List<_RosterUser> _roster = [];
  final Map<String, List<_JoinCode>> _codesByOrg = {};
  bool _loading = true;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = SupabaseService.client;
    var orgs = <_Org>[];
    var roster = <_RosterUser>[];
    if (client != null) {
      try {
        final rows = await client.from('organizations').select().order('name') as List;
        orgs = rows.map((r) {
          final m = r as Map<String, dynamic>;
          return _Org(
            id: m['id'] as String,
            name: m['name'] as String? ?? '',
            isDefault: m['is_default'] as bool? ?? false,
          );
        }).toList();
      } catch (_) {}
      try {
        final rows = await client.from('user_profiles').select('user_id, name, callsign, role, org_id') as List;
        roster = rows.map((r) {
          final m = r as Map<String, dynamic>;
          final callsign = m['callsign'] as String? ?? '';
          final name = m['name'] as String? ?? '';
          return _RosterUser(
            userId: m['user_id'] as String? ?? '',
            display: callsign.isNotEmpty ? callsign : (name.isNotEmpty ? name : (m['user_id'] as String? ?? '')),
            role: m['role'] as String? ?? 'member',
            orgId: m['org_id'] as String?,
          );
        }).where((u) => u.userId.isNotEmpty).toList();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _orgs = orgs;
        _roster = roster;
        _loading = false;
      });
    }
    for (final org in orgs) {
      _loadCodesFor(org.id);
    }
  }

  Future<void> _loadCodesFor(String orgId) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      final rows = await client.from('org_join_codes').select().eq('org_id', orgId).order('created_at', ascending: false) as List;
      final codes = rows.map((r) {
        final m = r as Map<String, dynamic>;
        return _JoinCode(id: m['id'] as String, code: m['code'] as String, isActive: m['is_active'] as bool? ?? true);
      }).toList();
      if (mounted) setState(() => _codesByOrg[orgId] = codes);
    } catch (_) {}
  }

  Future<void> _createOrg() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Organization'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Organization Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('organizations').insert({'name': name});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create organization: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _generateCode(_Org org) async {
    final client = SupabaseService.client;
    if (client == null) return;
    final code = _generateJoinCode();
    try {
      await client.from('org_join_codes').insert({'org_id': org.id, 'code': code});
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('New Join Code — ${org.name}'),
            content: SelectableText(code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
          ),
        );
      }
      _loadCodesFor(org.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate code: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleCode(_Org org, _JoinCode code) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('org_join_codes').update({'is_active': !code.isActive}).eq('id', code.id);
      _loadCodesFor(org.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update code: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _assignAdmin(_Org org) async {
    final searchCtrl = TextEditingController();
    final picked = await showDialog<_RosterUser>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final candidates = _roster.where((u) => u.display.toLowerCase().contains(query)).toList();
          return AlertDialog(
            title: Text('Assign Org Admin — ${org.name}'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(hintText: 'Search by name or callsign…', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: candidates.isEmpty
                      ? Center(child: Text('No users found.', style: TextStyle(color: Colors.grey[600])))
                      : ListView.builder(
                          itemCount: candidates.length,
                          itemBuilder: (_, i) {
                            final u = candidates[i];
                            return ListTile(
                              title: Text(u.display),
                              subtitle: Text(u.role == 'member' ? 'Member' : u.role == 'org_admin' ? 'Org Admin' : 'Super Admin'),
                              onTap: () => Navigator.pop(ctx, u),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').update({'role': 'org_admin', 'org_id': org.id}).eq('user_id', picked.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${picked.display} is now an admin for ${org.name}.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not assign admin: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _revokeAdmin(_RosterUser user) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').update({'role': 'member'}).eq('user_id', user.userId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not revoke admin: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizations'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _createOrg, icon: const Icon(Icons.add), label: const Text('New Organization')),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orgs.isEmpty
              ? Center(child: Text('No organizations yet.', style: TextStyle(color: Colors.grey[600])))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orgs.length,
                  itemBuilder: (_, i) {
                    final org = _orgs[i];
                    final admins = _roster.where((u) => u.orgId == org.id && u.role == 'org_admin').toList();
                    final codes = _codesByOrg[org.id] ?? const <_JoinCode>[];
                    final expanded = _expanded.contains(org.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(children: [
                        ListTile(
                          leading: const Icon(Icons.corporate_fare),
                          title: Text(org.name),
                          subtitle: Text(org.isDefault
                              ? 'Default bucket for users without a real organization'
                              : '${admins.length} admin(s) • ${codes.where((c) => c.isActive).length} active join code(s)'),
                          trailing: IconButton(
                            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                            onPressed: () => setState(() {
                              if (expanded) {
                                _expanded.remove(org.id);
                              } else {
                                _expanded.add(org.id);
                              }
                            }),
                          ),
                        ),
                        if (expanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Divider(),
                              Row(children: [
                                Text('Join Codes', style: Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: () => _generateCode(org),
                                  icon: const Icon(Icons.vpn_key_outlined),
                                  label: const Text('Generate Code'),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              if (codes.isEmpty)
                                Text('No join codes yet.', style: TextStyle(color: Colors.grey[600]))
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: codes.map((c) => InputChip(
                                        label: Text(c.code, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                                        avatar: Icon(c.isActive ? Icons.check_circle_outline : Icons.block, size: 18),
                                        backgroundColor: c.isActive ? null : Colors.grey.shade300,
                                        onPressed: () => _toggleCode(org, c),
                                        tooltip: c.isActive ? 'Tap to deactivate' : 'Tap to reactivate',
                                      )).toList(),
                                ),
                              const SizedBox(height: 16),
                              Row(children: [
                                Text('Admins', style: Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: () => _assignAdmin(org),
                                  icon: const Icon(Icons.person_add_alt_outlined),
                                  label: const Text('Assign Admin'),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              if (admins.isEmpty)
                                Text('No admins assigned yet.', style: TextStyle(color: Colors.grey[600]))
                              else
                                ...admins.map((a) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.admin_panel_settings_outlined),
                                      title: Text(a.display),
                                      trailing: TextButton(onPressed: () => _revokeAdmin(a), child: const Text('Revoke')),
                                    )),
                            ]),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }
}
