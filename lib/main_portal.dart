import 'package:flutter/material.dart';
import 'admin_console/console_auth.dart';
import 'admin_console/org_management_screen.dart';
import 'admin_console/protocols_console_screen.dart';
import 'protocol_admin.dart' show SupabaseService;

/// Entry point for the web-hosted Admin Portal -- a trimmed-down version of
/// the Windows Command Console (main_admin.dart) for organization admins to
/// manage personnel and push protocols from a browser (e.g. embedded at a
/// URL linked from peninsulathreat.com). Same Supabase backend, same
/// user_profiles.role/org_id, same RLS-enforced isolation as the desktop
/// Console and the mobile app -- nothing new to secure, just a second UI
/// surface for the org/protocols pieces of what the Console already does.
/// Deliberately excludes Incidents/Live Map/Assets/Deployment
/// Orders/Forms/Reports/Access Requests/Settings: the app is still primary
/// for field operations, this is only for the two things an org admin
/// needs on the web.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminPortalApp());
}

class AdminPortalApp extends StatefulWidget {
  const AdminPortalApp({super.key});

  @override
  State<AdminPortalApp> createState() => _AdminPortalAppState();
}

class _AdminPortalAppState extends State<AdminPortalApp> {
  bool _checking = true;
  ConsoleSession _session = ConsoleSession.signedOut;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await SupabaseService.ensureInitialized();
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
      title: 'ResQruck Admin Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark), useMaterial3: true),
      home: _checking
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _session.authed
              ? _PortalShell(session: _session, onSignOut: _signOut)
              : ConsoleSignInScreen(
                  appName: 'ResQruck Admin Portal',
                  tagline: 'Sign in with your organization admin account',
                  onSignedIn: (s) => setState(() => _session = s),
                ),
    );
  }
}

class _PortalShell extends StatefulWidget {
  final ConsoleSession session;
  final VoidCallback onSignOut;
  const _PortalShell({required this.session, required this.onSignOut});

  @override
  State<_PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<_PortalShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final isSuperAdmin = session.role == 'super_admin';
    final screens = [
      ProtocolsConsoleScreen(role: session.role, orgId: session.orgId, orgName: session.orgName),
      OrgManagementScreen(role: session.role, orgId: session.orgId),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                const Icon(Icons.shield_outlined, size: 32),
                const SizedBox(height: 12),
                if (!isSuperAdmin && session.orgName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(session.orgName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign Out',
                    onPressed: widget.onSignOut,
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: Text('Protocols')),
              NavigationRailDestination(
                  icon: Icon(Icons.corporate_fare_outlined),
                  selectedIcon: Icon(Icons.corporate_fare),
                  label: Text('Personnel')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: _index, children: screens)),
        ],
      ),
    );
  }
}
