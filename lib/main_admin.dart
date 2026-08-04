import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'admin_console/admin_shell.dart';
import 'protocol_admin.dart' show SupabaseService, showAdminPinDialog;

/// Entry point for the ResQruck Command Console (desktop-only incident
/// command app). Built via `flutter build windows -t lib/main_admin.dart`
/// or `flutter build macos -t lib/main_admin.dart` — the default entry
/// point (lib/main.dart) used by Android/iOS and the existing field-app
/// Windows/Mac build is completely untouched by this file.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1100, 700),
      center: true,
      title: 'ResQruck Command Console',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(const CommandConsoleApp());
}

class CommandConsoleApp extends StatefulWidget {
  const CommandConsoleApp({super.key});

  @override
  State<CommandConsoleApp> createState() => _CommandConsoleAppState();
}

class _CommandConsoleAppState extends State<CommandConsoleApp> {
  bool _checking = true;
  bool _authed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SupabaseService.ensureInitialized();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _authenticate(BuildContext context) async {
    final ok = await showAdminPinDialog(context);
    if (ok && mounted) setState(() => _authed = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResQruck Command Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: _checking
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _authed
              ? const AdminShellScreen()
              : _LockScreen(onUnlock: _authenticate),
    );
  }
}

class _LockScreen extends StatelessWidget {
  final void Function(BuildContext context) onUnlock;
  const _LockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('ResQruck Command Console', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Sign in with admin credentials to continue', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Sign In'),
            onPressed: () => onUnlock(context),
          ),
        ]),
      ),
    );
  }
}
