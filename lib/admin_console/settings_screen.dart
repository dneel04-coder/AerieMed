import 'package:flutter/material.dart';
import '../protocol_admin.dart' show ProtocolSyncService;
import '../team_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _teamDriveLink = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final link = await TeamSettingsService.getTeamDriveLink();
    if (mounted) setState(() { _teamDriveLink = link; _loading = false; });
  }

  Future<void> _changeCredentials(BuildContext context) async {
    final curUserCtrl = TextEditingController();
    final curPassCtrl = TextEditingController();
    final newUserCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Admin Credentials'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: curUserCtrl,
                decoration: const InputDecoration(labelText: 'Current Username', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: curPassCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password', border: OutlineInputBorder())),
            const Divider(height: 24),
            TextField(controller: newUserCtrl,
                decoration: const InputDecoration(labelText: 'New Username', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: newPassCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final correctUser = await ProtocolSyncService.instance.getAdminUsername();
    final correctPass = await ProtocolSyncService.instance.getAdminPassword();
    if (curUserCtrl.text.trim() != correctUser || curPassCtrl.text != correctPass) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current credentials incorrect')));
      }
      return;
    }
    final newUser = newUserCtrl.text.trim();
    final newPass = newPassCtrl.text;
    if (newUser.isEmpty || newPass.isEmpty) return;
    await ProtocolSyncService.instance.setAdminCredentials(newUser, newPass);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Credentials updated')));
    }
  }

  Future<void> _editTeamDriveLink(BuildContext context) async {
    final ctrl = TextEditingController(text: _teamDriveLink);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team Drive Link'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'A Dropbox / Google Drive / OneDrive shared-folder link. Field '
            'users see this when sending a report via "Send to Team Drive" '
            '— they get the link plus the OS share sheet with the PDF '
            'attached (Dropbox/Drive/OneDrive show up there automatically '
            'if installed).',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Shared folder link',
              hintText: 'https://www.dropbox.com/scl/fo/…',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final link = ctrl.text.trim();
    await TeamSettingsService.setTeamDriveLink(link);
    if (!mounted) return;
    setState(() => _teamDriveLink = link);
    ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Team drive link saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Admin Credentials'),
              subtitle: const Text('Shared with the mobile admin panel PIN'),
              trailing: FilledButton.tonal(
                onPressed: () => _changeCredentials(context),
                child: const Text('Change'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('Team Drive Link'),
              subtitle: Text(_loading
                  ? 'Loading…'
                  : (_teamDriveLink.isEmpty ? 'Not set — field app shows nothing yet' : _teamDriveLink)),
              trailing: FilledButton.tonal(
                onPressed: _loading ? null : () => _editTeamDriveLink(context),
                child: const Text('Edit'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
