import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'admin_console/admin_shell.dart';
import 'protocol_admin.dart' show SupabaseService;

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
  String _role = 'member';
  String? _orgId;
  String _orgName = '';

  @override
  void initState() {
    super.initState();
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maximizeWindow());
  }

  // Some window managers don't apply the SC_MAXIMIZE syscommand instantly on
  // first launch (race with the initial WM_SIZE/DPI messages) — a short
  // delay plus a setBounds fallback makes this reliable even when the
  // native maximize flag doesn't stick on the first attempt.
  Future<void> _maximizeWindow() async {
    await windowManager.maximize();
    await Future.delayed(const Duration(milliseconds: 300));
    if (await windowManager.isMaximized()) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    await windowManager.setBounds(Rect.fromLTWH(0, 0, screenSize.width, screenSize.height));
  }

  Future<void> _init() async {
    await SupabaseService.ensureInitialized();
    // supabase_flutter persists the session itself (secure local storage) --
    // if one's already there from a previous launch, this restores it
    // without prompting for credentials again.
    await _resolveSession();
    if (mounted) setState(() => _checking = false);
  }

  /// Looks up the signed-in user's own role/org and only admits
  /// org_admin/super_admin -- this (not a shared PIN) is now the entire
  /// access boundary for the Console. Anyone else is signed back out
  /// immediately.
  Future<void> _resolveSession() async {
    final client = SupabaseService.client;
    final session = client?.auth.currentSession;
    if (client == null || session == null) {
      _authed = false;
      return;
    }
    try {
      final row = await client
          .from('user_profiles')
          .select('role, org_id, organizations(name)')
          .eq('auth_user_id', session.user.id)
          .maybeSingle();
      final role = row?['role'] as String? ?? 'member';
      if (role != 'org_admin' && role != 'super_admin') {
        await client.auth.signOut();
        _authed = false;
        return;
      }
      _role = role;
      _orgId = row?['org_id'] as String?;
      // A super_admin oversees every organization, so their own nominal org
      // (usually the Legacy/Unassigned bucket) isn't meaningful to show.
      _orgName = role == 'super_admin' ? '' : ((row?['organizations'] as Map?)?['name'] as String? ?? '');
      _authed = true;
    } catch (_) {
      _authed = false;
    }
  }

  void _onSignedIn(String role, String? orgId, String orgName) {
    setState(() {
      _role = role;
      _orgId = orgId;
      _orgName = orgName;
      _authed = true;
    });
  }

  Future<void> _signOut() async {
    await SupabaseService.client?.auth.signOut();
    if (mounted) setState(() => _authed = false);
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
              ? AdminShellScreen(onSignOut: _signOut, role: _role, orgId: _orgId, orgName: _orgName)
              : _ConsoleSignInScreen(onSignedIn: _onSignedIn),
    );
  }
}

class _ConsoleSignInScreen extends StatefulWidget {
  final void Function(String role, String? orgId, String orgName) onSignedIn;
  const _ConsoleSignInScreen({required this.onSignedIn});

  @override
  State<_ConsoleSignInScreen> createState() => _ConsoleSignInScreenState();
}

class _ConsoleSignInScreenState extends State<_ConsoleSignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _signingIn = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Email and password are required.')));
      return;
    }
    setState(() => _signingIn = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot reach server. Check your connection.'), backgroundColor: Colors.red));
      setState(() => _signingIn = false);
      return;
    }
    final client = SupabaseService.client!;
    try {
      await client.auth.signInWithPassword(email: email, password: password);
      final userId = client.auth.currentUser!.id;
      final row = await client
          .from('user_profiles')
          .select('role, org_id, organizations(name)')
          .eq('auth_user_id', userId)
          .maybeSingle();
      final role = row?['role'] as String? ?? 'member';
      if (role != 'org_admin' && role != 'super_admin') {
        await client.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Access denied — ask your organization admin for Command Console access.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5)));
          setState(() => _signingIn = false);
        }
        return;
      }
      final orgId = row?['org_id'] as String?;
      final orgName = role == 'super_admin' ? '' : ((row?['organizations'] as Map?)?['name'] as String? ?? '');
      widget.onSignedIn(role, orgId, orgName);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Sign in failed: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
        setState(() => _signingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('ResQruck Command Console', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Sign in with your organization admin account',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              onSubmitted: (_) => _signIn(),
              decoration: const InputDecoration(
                  labelText: 'Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_outline)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: _signingIn
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_open_outlined),
              label: const Text('Sign In'),
              onPressed: _signingIn ? null : _signIn,
            ),
          ]),
        ),
      ),
    );
  }
}
