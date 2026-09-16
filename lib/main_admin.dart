import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'admin_console/admin_shell.dart';
import 'admin_console/console_auth.dart';
import 'protocol_admin.dart' show SupabaseService;

/// Entry point for the ResQruck Command Console (desktop-only incident
/// command app). Built via `flutter build windows -t lib/main_admin.dart`
/// or `flutter build macos -t lib/main_admin.dart` — the default entry
/// point (lib/main.dart) used by Android/iOS and the existing field-app
/// Windows/Mac build is completely untouched by this file. See
/// main_portal.dart for the web-hosted counterpart of this same shell,
/// sharing sign-in/session logic via admin_console/console_auth.dart.
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
  ConsoleSession _session = ConsoleSession.signedOut;

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
    final session = await restoreConsoleSession();
    if (mounted) setState(() { _session = session; _checking = false; });
  }

  Future<void> _signOut() async {
    await SupabaseService.client?.auth.signOut();
    if (mounted) setState(() => _session = ConsoleSession.signedOut);
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
          : _session.authed
              ? AdminShellScreen(
                  onSignOut: _signOut, role: _session.role, orgId: _session.orgId, orgName: _session.orgName)
              : ConsoleSignInScreen(onSignedIn: (s) => setState(() => _session = s)),
    );
  }
}
