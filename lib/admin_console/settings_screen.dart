import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserAttributes;
import '../protocol_admin.dart' show SupabaseService;
import '../team_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  const SettingsScreen({super.key, required this.onSignOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _teamDriveLinks = const ['', ''];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final links = await TeamSettingsService.getTeamDriveLinks();
      if (mounted) setState(() { _teamDriveLinks = links; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load team drive links: $e')));
      }
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: newPassCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password', hintText: 'At least 6 characters', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: confirmPassCtrl, obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final newPass = newPassCtrl.text;
    if (newPass.length < 6) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Password must be at least 6 characters.'), backgroundColor: Colors.red));
      }
      return;
    }
    if (newPass != confirmPassCtrl.text) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Passwords do not match.'), backgroundColor: Colors.red));
      }
      return;
    }
    try {
      final client = SupabaseService.client;
      if (client == null) throw Exception('Not connected');
      await client.auth.updateUser(UserAttributes(password: newPass));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update password: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _editTeamDriveLinks(BuildContext context) async {
    final ctrl1 = TextEditingController(text: _teamDriveLinks[0]);
    final ctrl2 = TextEditingController(text: _teamDriveLinks[1]);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team Drive Links'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Up to two Dropbox / Google Drive / OneDrive shared-folder links. '
            'Field users see both when sending a report via "Send to Team '
            'Drive" — they get the links plus the OS share sheet with the '
            'PDF attached, opened once per configured link (Dropbox/Drive/'
            'OneDrive show up there automatically if installed). Leave a '
            'field blank to not use that slot.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl1,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Team Drive Link 1',
              hintText: 'https://www.dropbox.com/scl/fo/…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl2,
            decoration: const InputDecoration(
              labelText: 'Team Drive Link 2',
              hintText: 'https://drive.google.com/drive/folders/…',
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
    final link1 = ctrl1.text.trim();
    final link2 = ctrl2.text.trim();
    try {
      await TeamSettingsService.setTeamDriveLinks(link1, link2);
      if (!mounted) return;
      setState(() => _teamDriveLinks = [link1, link2]);
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Team drive links saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context)
          .showSnackBar(SnackBar(content: Text('Could not save team drive links: $e')));
    }
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
              title: const Text('Password'),
              subtitle: const Text('Change the password for your Command Console account'),
              trailing: FilledButton.tonal(
                onPressed: () => _changePassword(context),
                child: const Text('Change'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_shared_outlined),
              title: const Text('Team Drive Links'),
              subtitle: Text(_loading
                  ? 'Loading…'
                  : (_teamDriveLinks.every((l) => l.isEmpty)
                      ? 'Not set — field app shows nothing yet'
                      : _teamDriveLinks.where((l) => l.isNotEmpty).join('\n'))),
              isThreeLine: !_loading && _teamDriveLinks.where((l) => l.isNotEmpty).length > 1,
              trailing: FilledButton.tonal(
                onPressed: _loading ? null : () => _editTeamDriveLinks(context),
                child: const Text('Edit'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              subtitle: const Text('Clears "stay signed in" and returns to the sign-in screen'),
              trailing: FilledButton.tonal(
                onPressed: widget.onSignOut,
                child: const Text('Sign Out'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
