import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_report.dart';

// ─── Shared Supabase singleton ────────────────────────────────────────────────

class SupabaseService {
  static const _urlKey = 'tac_supabase_url';
  static const _anonKey = 'tac_supabase_anon_key';
  static bool _initialized = false;

  static Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey) ?? '';
    final key = prefs.getString(_anonKey) ?? '';
    if (url.isEmpty || key.isEmpty) return false;
    try {
      await Supabase.initialize(url: url, anonKey: key);
      _initialized = true;
      return true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('already') || msg.contains('initialized')) {
        _initialized = true;
        return true;
      }
      return false;
    }
  }

  static SupabaseClient? get client => _initialized ? Supabase.instance.client : null;
}

// ─── Protocol model ───────────────────────────────────────────────────────────

class ProtocolEntry {
  final String id;
  final String name;
  final int version;
  final String filePath;
  final bool isActive;
  final DateTime updatedAt;
  final String updatedBy;
  final String notes;

  const ProtocolEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.filePath,
    required this.isActive,
    required this.updatedAt,
    required this.updatedBy,
    required this.notes,
  });

  factory ProtocolEntry.fromMap(Map<String, dynamic> m) => ProtocolEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        version: (m['version'] as num?)?.toInt() ?? 1,
        filePath: m['file_path'] as String,
        isActive: m['is_active'] as bool? ?? true,
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
        updatedBy: m['updated_by'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );

  String get localCacheName => '${id}_v$version.pdf';
}

// ─── Sync service ─────────────────────────────────────────────────────────────

class ProtocolSyncService {
  static final instance = ProtocolSyncService._();
  ProtocolSyncService._();

  static const _adminModeKey = 'proto_admin_mode';
  static const _adminUsernameKey = 'proto_admin_username';
  static const _adminPasswordKey = 'proto_admin_password';
  static const _userIdKey = 'tac_user_id';
  static const _callsignKey = 'tac_callsign';
  static const _defaultUsername = 't2ops';
  static const _defaultPassword = 'Lucas22!';

  Future<bool> get isAdminMode async =>
      (await SharedPreferences.getInstance()).getBool(_adminModeKey) ?? false;

  Future<void> setAdminMode(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_adminModeKey, value);

  Future<String> getAdminUsername() async =>
      (await SharedPreferences.getInstance()).getString(_adminUsernameKey) ?? _defaultUsername;

  Future<String> getAdminPassword() async =>
      (await SharedPreferences.getInstance()).getString(_adminPasswordKey) ?? _defaultPassword;

  Future<void> setAdminCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminUsernameKey, username);
    await prefs.setString(_adminPasswordKey, password);
  }

  Future<String> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_userIdKey);
    if (id == null) {
      final rng = Random.secure();
      id = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_userIdKey, id);
    }
    return id;
  }

  Future<String> _callsign() async =>
      (await SharedPreferences.getInstance()).getString(_callsignKey) ?? 'Unknown';

  String _newUuid() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<ProtocolEntry>> pendingProtocols() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      final userId = await _userId();
      final protocols = (await client.from('protocols').select().eq('is_active', true) as List)
          .map((r) => ProtocolEntry.fromMap(r as Map<String, dynamic>))
          .toList();
      final ackedIds = (await client
              .from('protocol_acknowledgments')
              .select('protocol_id')
              .eq('user_id', userId) as List)
          .map((a) => a['protocol_id'] as String)
          .toSet();
      return protocols.where((p) => !ackedIds.contains(p.id)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ProtocolEntry>> activeProtocols() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      return (await client.from('protocols').select().eq('is_active', true).order('name') as List)
          .map((r) => ProtocolEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ProtocolEntry>> allProtocols() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      return (await client
              .from('protocols')
              .select()
              .order('updated_at', ascending: false) as List)
          .map((r) => ProtocolEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<File?> downloadProtocol(ProtocolEntry entry) async {
    final client = SupabaseService.client;
    if (client == null) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/team_protocols/${entry.localCacheName}');
      if (await file.exists()) return file;
      await file.parent.create(recursive: true);
      final bytes = await client.storage.from('protocols').download(entry.filePath);
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> acknowledgeProtocol(String protocolId) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('protocol_acknowledgments').upsert({
        'user_id': await _userId(),
        'callsign': await _callsign(),
        'protocol_id': protocolId,
        'acknowledged_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,protocol_id');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAcknowledgments(String protocolId) async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      return (await client
              .from('protocol_acknowledgments')
              .select()
              .eq('protocol_id', protocolId)
              .order('acknowledged_at', ascending: false) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> uploadProtocol({
    required String name,
    required String notes,
    required Uint8List bytes,
    required String uploadedBy,
    String? existingId,
  }) async {
    final client = SupabaseService.client;
    if (client == null) throw Exception('Supabase not configured');
    final id = existingId ?? _newUuid();
    final filePath = '$id.pdf';
    await client.storage.from('protocols').uploadBinary(
      filePath,
      bytes,
      fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
    );
    if (existingId != null) {
      final row = await client.from('protocols').select('version').eq('id', existingId).single();
      final newVer = ((row['version'] as int?) ?? 1) + 1;
      await client.from('protocols').update({
        'version': newVer,
        'file_path': filePath,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': uploadedBy,
        'notes': notes,
        'is_active': true,
      }).eq('id', existingId);
      // Invalidate acknowledgments so users must re-acknowledge this version
      await client.from('protocol_acknowledgments').delete().eq('protocol_id', existingId);
    } else {
      await client.from('protocols').insert({
        'id': id,
        'name': name,
        'version': 1,
        'file_path': filePath,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': uploadedBy,
        'notes': notes,
      });
    }
  }

  Future<void> toggleActive(String id, bool active) async {
    await SupabaseService.client?.from('protocols').update({'is_active': active}).eq('id', id);
  }

  Future<void> deleteProtocol(ProtocolEntry entry) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.storage.from('protocols').remove([entry.filePath]);
    } catch (_) {}
    await client.from('protocols').delete().eq('id', entry.id);
  }

  Future<List<Map<String, dynamic>>> adminGetReports() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      return (await client
              .from('patient_reports')
              .select()
              .order('submitted_at', ascending: false) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> adminGetCerts() async {
    final client = SupabaseService.client;
    if (client == null) return [];
    try {
      return (await client
              .from('team_certs')
              .select()
              .order('callsign') as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}

// ─── Admin login dialog ───────────────────────────────────────────────────────

Future<bool> showAdminPinDialog(BuildContext context) async {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Admin Access'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: userCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enter')),
      ],
    ),
  );
  if (ok != true) return false;
  final correctUser = await ProtocolSyncService.instance.getAdminUsername();
  final correctPass = await ProtocolSyncService.instance.getAdminPassword();
  return userCtrl.text.trim() == correctUser && passCtrl.text == correctPass;
}

// ─── Protocol update dialog (startup) ────────────────────────────────────────

class ProtocolUpdateDialog extends StatefulWidget {
  final List<ProtocolEntry> protocols;
  const ProtocolUpdateDialog({required this.protocols, super.key});

  @override
  State<ProtocolUpdateDialog> createState() => _ProtocolUpdateDialogState();
}

class _ProtocolUpdateDialogState extends State<ProtocolUpdateDialog> {
  bool _acknowledging = false;

  Future<void> _ackAll() async {
    setState(() => _acknowledging = true);
    for (final p in widget.protocols) {
      await ProtocolSyncService.instance.acknowledgeProtocol(p.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.protocols.length;
    return AlertDialog(
      icon: const Icon(Icons.new_releases, color: Colors.orange, size: 32),
      title: Text('$n Protocol${n > 1 ? 's' : ''} Updated'),
      content: SizedBox(
        width: double.maxFinite,
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following protocol${n > 1 ? 's have' : ' has'} been updated. '
              'Tap each to see what changed, then acknowledge receipt.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: n,
                itemBuilder: (_, i) {
                  final p = widget.protocols[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ExpansionTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('v${p.version} — ${_fmt(p.updatedAt)}',
                          style: const TextStyle(fontSize: 11)),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      children: p.notes.isEmpty
                          ? []
                          : [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: Text(p.notes, style: const TextStyle(fontSize: 12)),
                              )
                            ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: _acknowledging ? null : _ackAll,
          icon: _acknowledging
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Acknowledge Receipt'),
        ),
      ],
    );
  }
}

// ─── Team Protocols screen (user view) ───────────────────────────────────────

class TeamProtocolsScreen extends StatefulWidget {
  const TeamProtocolsScreen({super.key});

  @override
  State<TeamProtocolsScreen> createState() => _TeamProtocolsScreenState();
}

class _TeamProtocolsScreenState extends State<TeamProtocolsScreen> {
  List<ProtocolEntry> _protocols = [];
  Set<String> _ackedIds = {};
  bool _loading = true;
  bool _notConfigured = false;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _notConfigured = false; });
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) {
      setState(() { _loading = false; _notConfigured = true; });
      return;
    }
    final protocols = await ProtocolSyncService.instance.activeProtocols();
    final pending = await ProtocolSyncService.instance.pendingProtocols();
    final pendingIds = pending.map((p) => p.id).toSet();
    setState(() {
      _protocols = protocols;
      _ackedIds = protocols.where((p) => !pendingIds.contains(p.id)).map((p) => p.id).toSet();
      _loading = false;
    });
  }

  Future<void> _viewProtocol(ProtocolEntry entry) async {
    setState(() => _downloading.add(entry.id));
    final file = await ProtocolSyncService.instance.downloadProtocol(entry);
    setState(() => _downloading.remove(entry.id));
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Download failed. Check your connection.')));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProtocolViewScreen(file: file, entry: entry)),
    );
    // Acknowledge after viewing
    await ProtocolSyncService.instance.acknowledgeProtocol(entry.id);
    if (mounted) setState(() => _ackedIds.add(entry.id));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_notConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Protocols')),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Supabase not configured', style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text('Open Tac Map to connect to your Supabase project.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Protocols'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _protocols.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No team protocols published yet.', style: TextStyle(color: Colors.grey)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _protocols.length,
              itemBuilder: (_, i) => _buildCard(_protocols[i]),
            ),
    );
  }

  Widget _buildCard(ProtocolEntry entry) {
    final acked = _ackedIds.contains(entry.id);
    final downloading = _downloading.contains(entry.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.red, size: 36),
            if (!acked)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                  child: const Text('NEW',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('v${entry.version}  •  Updated ${_fmt(entry.updatedAt)}',
              style: const TextStyle(fontSize: 11)),
          if (entry.notes.isNotEmpty)
            Text(entry.notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
        ]),
        isThreeLine: entry.notes.isNotEmpty,
        trailing: downloading
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                acked ? Icons.check_circle : Icons.download_outlined,
                color: acked ? Colors.green : Colors.blue,
              ),
        onTap: downloading ? null : () => _viewProtocol(entry),
      ),
    );
  }
}

class _ProtocolViewScreen extends StatelessWidget {
  final File file;
  final ProtocolEntry entry;
  const _ProtocolViewScreen({required this.file, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(entry.name, style: const TextStyle(fontSize: 15)),
          Text('v${entry.version}  •  ${_fmt(entry.updatedAt)}',
              style: const TextStyle(fontSize: 11)),
        ]),
      ),
      body: PdfViewer.file(file.path),
    );
  }
}

// ─── Admin panel ─────────────────────────────────────────────────────────────

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.blue, child: Icon(Icons.description, color: Colors.white)),
            title: const Text('Protocol Management'),
            subtitle: const Text('Upload, update, and manage team protocols'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminProtocolScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.red, child: Icon(Icons.assignment, color: Colors.white)),
            title: const Text('Patient Reports'),
            subtitle: const Text('View all reports submitted by the team'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminReportsScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.workspace_premium, color: Colors.white)),
            title: const Text('Team Certifications'),
            subtitle: const Text('View certifications for all team members'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminCertsScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.grey, child: Icon(Icons.lock_outline, color: Colors.white)),
            title: const Text('Change Admin Credentials'),
            onTap: () => _changeCredentialsDialog(context),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCredentialsDialog(BuildContext context) async {
    final curUserCtrl = TextEditingController();
    final curPassCtrl = TextEditingController();
    final newUserCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Admin Credentials'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: curUserCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Current Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: curPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Current Password', border: OutlineInputBorder()),
            ),
            const Divider(height: 24),
            TextField(
              controller: newUserCtrl,
              decoration: const InputDecoration(
                  labelText: 'New Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New Password', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final correctUser = await ProtocolSyncService.instance.getAdminUsername();
    final correctPass = await ProtocolSyncService.instance.getAdminPassword();
    if (curUserCtrl.text.trim() != correctUser || curPassCtrl.text != correctPass) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Current credentials incorrect')));
      }
      return;
    }
    final newUser = newUserCtrl.text.trim();
    final newPass = newPassCtrl.text;
    if (newUser.isEmpty || newPass.isEmpty) return;
    await ProtocolSyncService.instance.setAdminCredentials(newUser, newPass);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Credentials updated')));
    }
  }
}

// ─── Admin: Protocol management ───────────────────────────────────────────────

class AdminProtocolScreen extends StatefulWidget {
  const AdminProtocolScreen({super.key});

  @override
  State<AdminProtocolScreen> createState() => _AdminProtocolScreenState();
}

class _AdminProtocolScreenState extends State<AdminProtocolScreen> {
  List<ProtocolEntry> _protocols = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final protocols = await ProtocolSyncService.instance.allProtocols();
    if (mounted) setState(() { _protocols = protocols; _loading = false; });
  }

  Future<void> _showUploadSheet({ProtocolEntry? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final notesCtrl = TextEditingController();
    Uint8List? bytes;
    String? fileName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  existing == null ? 'Upload New Protocol' : 'Update — ${existing.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                if (existing == null) ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Protocol Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: existing == null ? 'Notes / Description' : 'What changed in this version?',
                    hintText: 'Added dosing table, updated contraindications…',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(fileName ?? 'Choose PDF'),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
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
                    child: Text(fileName ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                const SizedBox(height: 16),
                _UploadButton(
                  existing: existing,
                  nameCtrl: nameCtrl,
                  notesCtrl: notesCtrl,
                  bytes: bytes,
                  onSuccess: () {
                    Navigator.pop(ctx);
                    _load();
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAcks(ProtocolEntry entry) async {
    final acks = await ProtocolSyncService.instance.getAcknowledgments(entry.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Acknowledgments — ${entry.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          acks.isEmpty
              ? const Expanded(
                  child: Center(child: Text('No acknowledgments yet', style: TextStyle(color: Colors.grey))))
              : Expanded(
                  child: ListView.builder(
                    itemCount: acks.length,
                    itemBuilder: (_, i) {
                      final a = acks[i];
                      final dt = DateTime.tryParse(a['acknowledged_at'] as String? ?? '');
                      return ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(a['callsign'] as String? ?? 'Unknown'),
                        subtitle: dt != null ? Text(_fmt(dt)) : null,
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ProtocolEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Protocol?'),
        content: Text('Permanently delete "${entry.name}"? '
            'This removes the file and all acknowledgment records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProtocolSyncService.instance.deleteProtocol(entry);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocol Management'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.code), tooltip: 'View SQL Schema', onPressed: _showSchema),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(),
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Protocol'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _protocols.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No protocols uploaded yet'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _showUploadSheet(),
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload First Protocol'),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _protocols.length,
                  itemBuilder: (_, i) => _buildCard(_protocols[i]),
                ),
    );
  }

  Widget _buildCard(ProtocolEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(Icons.picture_as_pdf,
                color: entry.isActive ? Colors.red : Colors.grey, size: 32),
            title: Row(children: [
              Expanded(
                  child: Text(entry.name,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: entry.isActive ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entry.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('v${entry.version}  •  ${_fmt(entry.updatedAt)}  •  by ${entry.updatedBy}',
                  style: const TextStyle(fontSize: 11)),
              if (entry.notes.isNotEmpty)
                Text(entry.notes,
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
            ]),
            isThreeLine: entry.notes.isNotEmpty,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.update, size: 16),
                label: const Text('Update'),
                onPressed: () => _showUploadSheet(existing: entry),
              ),
              TextButton.icon(
                icon: const Icon(Icons.people_outline, size: 16),
                label: const Text('Acks'),
                onPressed: () => _showAcks(entry),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  entry.isActive ? Icons.toggle_on : Icons.toggle_off,
                  color: entry.isActive ? Colors.green : Colors.grey,
                  size: 28,
                ),
                tooltip: entry.isActive ? 'Deactivate' : 'Activate',
                onPressed: () async {
                  await ProtocolSyncService.instance.toggleActive(entry.id, !entry.isActive);
                  _load();
                },
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                onPressed: () => _confirmDelete(entry),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  void _showSchema() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supabase SQL — Run in SQL Editor'),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              _kAdditionalSql,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }
}

// Stateful upload button to handle uploading state inside bottom sheet
class _UploadButton extends StatefulWidget {
  final ProtocolEntry? existing;
  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;
  final Uint8List? bytes;
  final VoidCallback onSuccess;
  const _UploadButton({
    required this.existing,
    required this.nameCtrl,
    required this.notesCtrl,
    required this.bytes,
    required this.onSuccess,
  });

  @override
  State<_UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<_UploadButton> {
  bool _uploading = false;

  Future<void> _upload() async {
    if (widget.bytes == null) return;
    final name = widget.existing?.name ?? widget.nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _uploading = true);
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString('tac_callsign') ?? 'Admin';
    try {
      await ProtocolSyncService.instance.uploadProtocol(
        name: name,
        notes: widget.notesCtrl.text.trim(),
        bytes: widget.bytes!,
        uploadedBy: callsign,
        existingId: widget.existing?.id,
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
    final canUpload = widget.bytes != null &&
        !_uploading &&
        (widget.existing != null || widget.nameCtrl.text.trim().isNotEmpty);
    return FilledButton.icon(
      onPressed: canUpload ? _upload : null,
      icon: _uploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(widget.existing == null ? Icons.cloud_upload : Icons.update),
      label: Text(_uploading
          ? 'Uploading…'
          : widget.existing == null
              ? 'Upload Protocol'
              : 'Push Update'),
    );
  }
}

// ─── Admin: Patient reports ───────────────────────────────────────────────────

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ProtocolSyncService.instance.adminGetReports();
    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  void _viewReport(Map<String, dynamic> row) {
    try {
      final report = PatientReport.fromJson(row['report_data'] as Map<String, dynamic>);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              report.formattedText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not parse report data')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patient Reports (${_rows.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Text('No reports submitted yet.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final row = _rows[i];
                    final data = (row['report_data'] as Map?)?.cast<String, dynamic>() ?? {};
                    final patientId = data['patientId'] as String? ?? '';
                    final formType = data['formType'] as String? ?? 'MIST';
                    final callsign = row['callsign'] as String? ?? 'Unknown';
                    final submitted =
                        DateTime.tryParse(row['submitted_at'] as String? ?? '');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.12),
                          child: Text(formType == 'Pediatric' ? 'PED' : formType,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                        ),
                        title: Text(
                            patientId.isEmpty ? 'Unknown Patient' : patientId,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From: $callsign'),
                              if (submitted != null)
                                Text(_fmt(submitted),
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ]),
                        isThreeLine: true,
                        trailing: TextButton(
                            onPressed: () => _viewReport(row), child: const Text('View')),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── Admin: Team certifications ──────────────────────────────────────────────

class AdminCertsScreen extends StatefulWidget {
  const AdminCertsScreen({super.key});

  @override
  State<AdminCertsScreen> createState() => _AdminCertsScreenState();
}

class _AdminCertsScreenState extends State<AdminCertsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ProtocolSyncService.instance.adminGetCerts();
    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  Map<String, List<Map<String, dynamic>>> _grouped() {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final row in _rows) {
      final callsign = row['callsign'] as String? ?? 'Unknown';
      groups.putIfAbsent(callsign, () => []).add(row);
    }
    return groups;
  }

  Future<void> _viewCert(Map<String, dynamic> row) async {
    final client = SupabaseService.client;
    if (client == null) return;
    final filePath = row['file_path'] as String? ?? '';
    if (filePath.isEmpty) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading…'),
          ]),
        ),
      ),
    );

    try {
      final bytes = await client.storage.from('certs').download(filePath);
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      final isPdf = filePath.toLowerCase().endsWith('.pdf');
      if (isPdf) {
        final dir = await getTemporaryDirectory();
        final tempFile = File('${dir.path}/cert_${row['id']}.pdf');
        await tempFile.writeAsBytes(bytes);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: Text('${row['license_type']} — ${row['callsign']}',
                    style: const TextStyle(fontSize: 14)),
              ),
              body: PdfViewer.file(tempFile.path),
            ),
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text('${row['license_type']} — ${row['callsign']}',
                    style: const TextStyle(fontSize: 14)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              InteractiveViewer(child: Image.memory(bytes)),
            ]),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load cert: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final groups = _grouped();

    return Scaffold(
      appBar: AppBar(
        title: Text('Team Certifications (${_rows.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _rows.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No certifications synced yet.', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 8),
                Text('Certs are uploaded when team members add them in Cert Vault.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final callsign = groups.keys.elementAt(i);
                final certs = groups[callsign]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepOrange.withValues(alpha: 0.15),
                      child: const Icon(Icons.person, color: Colors.deepOrange),
                    ),
                    title: Text(callsign,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${certs.length} cert${certs.length != 1 ? 's' : ''}'),
                    initiallyExpanded: true,
                    children: certs.map((cert) {
                      final dt =
                          DateTime.tryParse(cert['uploaded_at'] as String? ?? '');
                      return ListTile(
                        leading:
                            const Icon(Icons.workspace_premium, color: Colors.amber),
                        title: Text(cert['license_type'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cert['state'] as String? ?? ''),
                              if (dt != null)
                                Text('Uploaded ${_fmt(dt)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            ]),
                        isThreeLine: true,
                        trailing: TextButton(
                          onPressed: () => _viewCert(cert),
                          child: const Text('View'),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}

// ─── SQL schema constant ──────────────────────────────────────────────────────

const _kAdditionalSql = '''
-- Run in Supabase SQL Editor (separate from Tac Map schema)

create table protocols (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  version int not null default 1,
  file_path text not null,
  is_active boolean default true,
  updated_at timestamptz default now(),
  updated_by text default '',
  notes text default ''
);

create table protocol_acknowledgments (
  id uuid default gen_random_uuid() primary key,
  user_id text not null,
  callsign text not null,
  protocol_id uuid references protocols(id) on delete cascade,
  acknowledged_at timestamptz default now(),
  unique(user_id, protocol_id)
);

create table patient_reports (
  id text primary key,
  user_id text not null,
  callsign text not null,
  report_data jsonb not null,
  submitted_at timestamptz default now()
);

alter table protocols enable row level security;
alter table protocol_acknowledgments enable row level security;
alter table patient_reports enable row level security;

create policy "public_access" on protocols
  for all using (true) with check (true);
create policy "public_access" on protocol_acknowledgments
  for all using (true) with check (true);
create policy "public_access" on patient_reports
  for all using (true) with check (true);

insert into storage.buckets (id, name, public)
  values ('protocols', 'protocols', true)
  on conflict (id) do nothing;

create policy "public_protocols" on storage.objects
  for all using (bucket_id = 'protocols')
  with check (bucket_id = 'protocols');

-- Team certifications (run these if adding cert sync)

create table team_certs (
  id text primary key,
  user_id text not null,
  callsign text not null,
  license_type text not null,
  state text not null,
  original_file_name text not null,
  uploaded_at timestamptz not null,
  file_path text not null
);

alter table team_certs enable row level security;
create policy "public_access" on team_certs
  for all using (true) with check (true);

insert into storage.buckets (id, name, public)
  values ('certs', 'certs', false)
  on conflict (id) do nothing;

create policy "public_certs" on storage.objects
  for all using (bucket_id = 'certs')
  with check (bucket_id = 'certs');
''';

// ─── Shared date formatter ────────────────────────────────────────────────────

String _fmt(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
