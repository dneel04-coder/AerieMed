import 'package:flutter/material.dart';
import '../protocol_admin.dart' show ProtocolSyncService;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        ],
      ),
    );
  }
}
