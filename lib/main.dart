import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'paywall_screen.dart';
import 'resqruck_assistant.dart';
import 'user_profile.dart';
import 'patient_report.dart';
import 'decision_tree.dart';
import 'drug_reference.dart';
import 'procedure_checklist.dart';
import 'differential_dx.dart';
import 'dosing_calculator.dart';
import 'protocol_version.dart';
import 'team_command.dart';
import 'mci_triage.dart';
import 'cert_vault.dart';
import 'tac_map.dart';
import 'incident_service.dart';
import 'protocol_admin.dart';
import 'backcountry_guide.dart';
import 'rems_checklist.dart';
import 'push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the Android navigation bar (edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ResQruckApp());
}

class ResQruckApp extends StatefulWidget {
  const ResQruckApp({super.key});

  @override
  State<ResQruckApp> createState() => _ResQruckAppState();
}

bool get _isDesktopWindow =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class _ResQruckAppState extends State<ResQruckApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _loggedIn = false;
  bool _authChecked = false;
  // 'pending' | 'denied' | null (no self-serve request outstanding — the
  // access-code path is unaffected and falls through to normal LoginScreen).
  String? _accessStatus;
  String _deviceUserId = '';

  @override
  void initState() {
    super.initState();
    _loadTheme();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final loggedIn = await UserProfile.isLoggedIn();
    if (!loggedIn) {
      final profile = await UserProfile.load();
      final status = await UserProfile.fetchAccessRequestStatus(profile.userId);
      if (mounted) {
        setState(() {
          _deviceUserId = profile.userId;
          _accessStatus = (status == 'pending' || status == 'denied') ? status : null;
          _loggedIn = false;
          _authChecked = true;
        });
      }
      return;
    }
    if (mounted) setState(() { _loggedIn = loggedIn; _authChecked = true; });
  }

  void _logout() async {
    await UserProfile.logout();
    if (mounted) setState(() => _loggedIn = false);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode');
    if (isDark != null) {
      setState(() {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResQruck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      builder: (context, child) {
        // Prevent content from going under the Android navigation bar on all screens.
        final content = SafeArea(top: false, child: child!);
        if (!_isDesktopWindow) return content;
        // The UI was designed for phone-width screens — grids and cards stretch
        // into oversized, awkward shapes on a wide desktop window. Rather than
        // touch every screen's layout, letterbox the untouched phone UI inside
        // a fixed-width frame so Android/iOS stay pixel-identical.
        final brightness = Theme.of(context).brightness;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: brightness == Brightness.dark
                  ? const [Color(0xFF0B0B12), Color(0xFF1B1330)]
                  : const [Color(0xFFE8EAF6), Color(0xFFFBE9E7)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ]),
                child: content,
              ),
            ),
          ),
        );
      },
      home: !_authChecked
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _loggedIn
              ? MainShell(onThemeToggle: toggleTheme, onLogout: _logout)
              : _accessStatus != null
                  ? AccessPendingScreen(
                      userId: _deviceUserId,
                      onApproved: () {
                        if (mounted) setState(() => _accessStatus = null);
                      },
                    )
                  : LoginScreen(onLoggedIn: () {
                      if (mounted) setState(() => _loggedIn = true);
                    }),
    );
  }
}

// ── Bottom-nav shell ─────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onThemeToggle, required this.onLogout});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 2; // start on Med
  bool _isAdmin = false;
  bool _unlocked = false;
  RealtimeChannel? _alertChannel;
  RealtimeChannel? _missionChannel;
  bool _showingMissionPrompt = false;

  @override
  void initState() {
    super.initState();
    UserProfile.isUnlocked().then((v) {
      if (mounted) setState(() => _unlocked = v);
    });
    ProtocolSyncService.instance.isAdminMode.then((v) {
      if (!mounted) return;
      setState(() => _isAdmin = v);
      if (v) _subscribeToAlerts();
    });
    // Run the mission-assignment check after the update dialog resolves —
    // both use a non-dismissible AlertDialog and shouldn't race to
    // showDialog on the same Navigator at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForUpdate();
      _checkPendingMissionAssignment();
      _subscribeMissionAssignments();
      _initPushNotifications();
    });
  }

  Future<void> _showPaywall() async {
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    if ((unlocked ?? false) && mounted) setState(() => _unlocked = true);
  }

  @override
  void dispose() {
    _alertChannel?.unsubscribe();
    _missionChannel?.unsubscribe();
    super.dispose();
  }

  // ── Mission assignment (Command Console → field device) ──────────────────

  Future<void> _initPushNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('tac_user_id') ?? '';
    await PushNotificationService.instance.initialize(userId);
  }

  Future<void> _checkPendingMissionAssignment() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('tac_user_id') ?? '';
    if (userId.isEmpty || !mounted) return;
    final pending = await IncidentService.instance.fetchPendingForUser(userId);
    if (pending.isNotEmpty) _showMissionAssignmentPrompt(pending.first);
  }

  Future<void> _subscribeMissionAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('tac_user_id') ?? '';
    if (userId.isEmpty) return;
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    _missionChannel?.unsubscribe();
    _missionChannel = SupabaseService.client!
        .channel('incident_members_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incident_members',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            if (!mounted) return;
            final r = payload.newRecord;
            if (r['accepted_at'] == null && r['left_at'] == null) {
              _checkPendingMissionAssignment();
            }
          },
        )
        .subscribe();
  }

  Future<void> _showMissionAssignmentPrompt(PendingAssignment pending) async {
    if (_showingMissionPrompt || !mounted) return;
    _showingMissionPrompt = true;
    final incident = pending.incident;
    final label = incident.name.isEmpty ? incident.missionCode : incident.name;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Mission Assignment'),
        icon: const Icon(Icons.local_fire_department_outlined),
        content: Text('You\'ve been assigned to mission: $label'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not Now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept')),
        ],
      ),
    );
    _showingMissionPrompt = false;
    if (accepted != true || !mounted) return;
    await IncidentService.instance.acceptMembership(pending.member.id);
    final profile = await UserProfile.load();
    await joinMissionSilently(callsign: profile.displayCallsign, missionCode: incident.missionCode);
  }

  Future<void> _subscribeToAlerts() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    _alertChannel?.unsubscribe();
    _alertChannel = SupabaseService.client!
        .channel('admin_alerts_feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'admin_alerts',
          callback: (payload) {
            if (!mounted || !_isAdmin) return;
            final r = payload.newRecord;
            final title = r['title'] as String? ?? 'Alert';
            final callsign = r['callsign'] as String? ?? '';
            final msg = callsign.isNotEmpty ? '$title — $callsign' : title;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(msg),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
              ),
            ));
          },
        )
        .subscribe();
  }

  Future<void> _checkForUpdate() async {
    if (!Platform.isAndroid) return; // Play Store in-app updates are Android-only
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (!mounted) return;
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        _showUpdateDialog();
      }
    } catch (_) {
      // Not on Play Store / no connectivity — ignore
    }
  }

  void _showUpdateDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Available'),
        content: const Text(
          'A new version of ResQruck is available. Update now to get the latest protocols and features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _startUpdate();
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _startUpdate() async {
    try {
      await InAppUpdate.startFlexibleUpdate();
      _listenForDownloadCompletion();
    } catch (_) {
      // Play Store not available — ignore
    }
  }

  void _listenForDownloadCompletion() {
    InAppUpdate.checkForUpdate().then((info) async {
      if (!mounted) return;
      if (info.installStatus == InstallStatus.downloaded) {
        _showRestartBanner();
      }
    });
  }

  void _showRestartBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text('Update downloaded — restart to apply.'),
        leading: const Icon(Icons.system_update),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              await InAppUpdate.completeFlexibleUpdate();
            },
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  Future<void> _onTabTap(int index) async {
    // Tab 2 (Home) is always visible; tab 4 (Admin) has its own PIN gate.
    if (!_unlocked && index != 2 && index != 4) {
      await _showPaywall();
      return;
    }
    if (index == 4 && !_isAdmin) {
      final ok = await showAdminPinDialog(context);
      if (!ok || !mounted) return;
      await ProtocolSyncService.instance.setAdminMode(true);
      if (mounted) setState(() { _isAdmin = true; _tab = 4; });
      _subscribeToAlerts();
      return;
    }
    setState(() => _tab = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const TeamCommandScreen(),
          const TacMapScreen(),
          MedHomeScreen(
            onThemeToggle: widget.onThemeToggle,
            onLogout: widget.onLogout,
            isUnlocked: _unlocked,
            onPaywallTap: _showPaywall,
          ),
          const CertVaultScreen(),
          _AdminShell(
            isAdmin: _isAdmin,
            onUnlocked: () => setState(() { _isAdmin = true; _tab = 4; }),
            onLeaveAdmin: () async {
              await ProtocolSyncService.instance.setAdminMode(false);
              if (mounted) setState(() { _isAdmin = false; _tab = 2; });
            },
          ),
        ],
      ),
      floatingActionButton: _tab != 1
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AssistantFab(),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'compass_fab',
                  onPressed: () async {
                    if (!_unlocked) { await _showPaywall(); return; }
                    setState(() => _tab = 1);
                  },
                  tooltip: 'Open Tac Map',
                  child: const Icon(Icons.explore),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _onTabTap,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.people_outlined),
              selectedIcon: Icon(Icons.people),
              label: 'Team'),
          NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.workspace_premium_outlined),
              selectedIcon: Icon(Icons.workspace_premium),
              label: 'Certs'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Admin'),
        ],
      ),
    );
  }
}


// ── Med accent color ─────────────────────────────────────────────────────────

const Color kMedRed = Color(0xFFCC2222);

// ── MedHomeScreen ─────────────────────────────────────────────────────────────

class MedHomeScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final VoidCallback onLogout;
  final bool isUnlocked;
  final VoidCallback onPaywallTap;
  const MedHomeScreen({
    super.key,
    required this.onThemeToggle,
    required this.onLogout,
    required this.isUnlocked,
    required this.onPaywallTap,
  });

  @override
  State<MedHomeScreen> createState() => _MedHomeScreenState();
}

class _MedHomeScreenState extends State<MedHomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _openSearch(String query) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TableOfContentsScreen(
          onThemeToggle: widget.onThemeToggle,
          onLogout: widget.onLogout,
          protocolsOnly: true,
          initialSearch: query),
    ));
  }

  @override
  Widget build(BuildContext context) {
    VoidCallback gated(VoidCallback action) =>
        widget.isUnlocked ? action : widget.onPaywallTap;

    final cards = [
      _MedCardData(Icons.menu_book,         'Protocols',     const Color(0xFFCC2222), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => TableOfContentsScreen(onThemeToggle: widget.onThemeToggle, onLogout: widget.onLogout, protocolsOnly: true))))),
      _MedCardData(Icons.medication,         'Drug & Dosing', const Color(0xFF1565C0), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const DrugDosingScreen())))),
      _MedCardData(Icons.account_tree,       'Decision Tree', const Color(0xFF6A1B9A), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const DecisionTreeScreen())))),
      _MedCardData(Icons.checklist_outlined, 'Procedures',   const Color(0xFF2E7D32), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProcedureListScreen())))),
      _MedCardData(Icons.emergency,          'MCI Triage',   const Color(0xFFE65100), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const MciTriageScreen())))),
      _MedCardData(Icons.assignment_outlined,'Patient Report',const Color(0xFF00695C), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const PatientReportListScreen())))),
      _MedCardData(Icons.terrain,            'Field Guide',  const Color(0xFF4E6B3A), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackcountryGuideScreen())))),
      _MedCardData(Icons.checklist_rtl,      'Pre-Deploy\nChecklist', const Color(0xFF0277BD), gated(() => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemsChecklistScreen())))),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kMedRed,
        foregroundColor: Colors.white,
        title: const Text('ResQruck Med',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.brightness_medium, color: Colors.white),
              onPressed: widget.onThemeToggle),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (v) { if (v == 'logout') widget.onLogout(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout',
                  child: ListTile(
                      leading: Icon(Icons.logout, color: Colors.red),
                      title: Text('Log Out'),
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: cards.length,
                itemBuilder: (_, i) => _MedCard(data: cards[i], locked: !widget.isUnlocked),
              ),
            ),
          ),
          // True search bar — opens protocol browser pre-filtered.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (q) => _openSearch(q.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search protocols, meds, procedures…',
                prefixIcon: const Icon(Icons.search, color: kMedRed),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchCtrl.clear()))
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kMedRed)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kMedRed, width: 2)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: kMedRed.withValues(alpha: 0.5))),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedCardData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MedCardData(this.icon, this.label, this.color, this.onTap);
}

class _MedCard extends StatelessWidget {
  final _MedCardData data;
  final bool locked;
  const _MedCard({required this.data, this.locked = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    return Stack(
      children: [
        Card(
          color: bg,
          clipBehavior: Clip.hardEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: data.color, width: 2),
          ),
          elevation: 3,
          child: InkWell(
            onTap: data.onTap,
            splashColor: data.color.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(data.icon, size: 48, color: data.color),
                  const SizedBox(height: 12),
                  Text(
                    data.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (locked)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.black.withValues(alpha: 0.38),
                child: const Center(
                  child: Icon(Icons.lock_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
      ],
    );
  }
}


// ── Drug & Dosing (merged screen) ────────────────────────────────────────────

class DrugDosingScreen extends StatelessWidget {
  const DrugDosingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: kMedRed,
          foregroundColor: Colors.white,
          title: const Text('Drug & Dosing',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.medication_liquid), text: 'Drug Reference'),
              Tab(icon: Icon(Icons.calculate), text: 'Dosing Calculator'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DrugReferenceScreen(embedded: true),
            DosingCalculatorScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}


// ── Admin tab shell ───────────────────────────────────────────────────────────

class _AdminShell extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onUnlocked;
  final VoidCallback onLeaveAdmin;
  const _AdminShell({required this.isAdmin, required this.onUnlocked, required this.onLeaveAdmin});

  @override
  Widget build(BuildContext context) {
    if (isAdmin) return AdminPanelScreen(onLeaveAdmin: onLeaveAdmin);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 72, color: cs.primary),
          const SizedBox(height: 16),
          const Text('Admin Area',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Enter your admin credentials to continue',
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 28),
          FilledButton.icon(
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Enter Credentials'),
            onPressed: () async {
              final ok = await showAdminPinDialog(context);
              if (ok) {
                await ProtocolSyncService.instance.setAdminMode(true);
                onUnlocked();
              }
            },
          ),
        ]),
      ),
    );
  }
}


// ── Protocol list (drawer content) ───────────────────────────────────────────

class TableOfContentsScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final VoidCallback? onLogout;
  final bool protocolsOnly;
  final String initialSearch;
  const TableOfContentsScreen({
    super.key,
    required this.onThemeToggle,
    this.onLogout,
    this.protocolsOnly = false,
    this.initialSearch = '',
  });

  @override
  State<TableOfContentsScreen> createState() => _TableOfContentsScreenState();
}

class _TableOfContentsScreenState extends State<TableOfContentsScreen> {
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Set<String> favorites = {};
  List<Map<String, String>> userUploads = [];

  final Map<String, Map<String, dynamic>> medicationData = {
    'Acetaminophen': {'types': ['Pain Management'], 'abc': []},
    'Adenosine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Albuterol': {'types': ['Respiratory'], 'abc': ['breathing']},
    'Amiodarone': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Aspirin': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Atropine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Calcium Chloride': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Dexamethasone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Diphenhydramine': {'types': ['Allergy & Anaphylaxis'], 'abc': []},
    'Droperidol': {'types': ['Sedation & Seizure'], 'abc': []},
    'Duo-Dote': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Epinephrine': {'types': ['Allergy & Anaphylaxis', 'Respiratory', 'Cardiac & Circulation'], 'abc': ['breathing', 'circulation']},
    'Fentanyl': {'types': ['Pain Management'], 'abc': []},
    'Glucagon': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Glucose Gel': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Hydromorphone': {'types': ['Pain Management'], 'abc': []},
    'Ipratropium': {'types': ['Respiratory'], 'abc': ['breathing']},
    'Ketamine': {'types': ['Pain Management', 'Sedation & Seizure'], 'abc': ['airway']},
    'Ketorolac': {'types': ['Pain Management'], 'abc': []},
    'Lidocaine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Magnesium Sulfate': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Metoprolol': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Methylprednisolone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Midazolam': {'types': ['Sedation & Seizure'], 'abc': ['airway']},
    'Naloxone': {'types': ['Antidotes & Metabolic'], 'abc': []},
    'Nitroglycerin': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Norepinephrine': {'types': ['Cardiac & Circulation'], 'abc': ['circulation']},
    'Ondansetron': {'types': ['Others'], 'abc': []},
    'Prednisone': {'types': ['Allergy & Anaphylaxis', 'Respiratory'], 'abc': ['breathing']},
    'Rocuronium': {'types': ['Others'], 'abc': ['airway']},
    'Sodium Bicarbonate': {'types': ['Cardiac & Circulation', 'Antidotes & Metabolic'], 'abc': ['circulation']},
    'Tetracaine': {'types': ['Others'], 'abc': []},
    'Tranexamic Acid': {'types': ['Others'], 'abc': ['circulation']},
  };

  final List<Map<String, dynamic>> staticCategories = [
    {
      'title': 'Appendix Material',
      'items': [
        {'title': 'EXPANDED SCOPE - california version', 'asset': 'EXPANDED SCOPE - california version.pdf'},
        {'title': 'Igel - Ideal Body Weight Chart', 'asset': 'Igel - Ideal Body Weight Chart.pdf'},
        {'title': 'APGAR', 'asset': 'APGAR.pdf'},
        {'title': 'Glasgow Coma Scale', 'asset': 'GCS.pdf'},
        {'title': 'Pediatric Normal Vital Signs', 'asset': 'Pediatric Normal Vital Signs.pdf'},
        {'title': 'Pain Rating Scales', 'asset': 'Pain Rating Scales.pdf'},
        {'title': 'Sedation Score', 'asset': 'Sedation Score.pdf'},
        {'title': 'Acceptable Abbreviations for PCR', 'asset': 'Acceptable Abbreviations for PCR.pdf'},
        {'title': 'Stroke Alert Criteria', 'asset': 'Stroke Alert Criteria.pdf'},
        {'title': 'Respiratory Treatments Guide', 'asset': 'Respiratory Treatments Guide.pdf'},
      ]
    },
    {
      'title': 'Procedures',
      'items': [
        {'title': 'Synchronized Cardioversion', 'asset': 'Synchronized Cardioversion.pdf'},
        {'title': 'Transcutaneous Pacing', 'asset': 'Transcutaneous Pacing.pdf'},
        {'title': 'Nasogastric and Orogastric Tubes', 'asset': 'Nasogastric and Orogastric Tubes.pdf'},
        {'title': 'Failed Airway', 'asset': 'Failed Airway.pdf'},
        {'title': 'Finger Thoracostomy Procedure', 'asset': 'Finger Thoracostomy Procedure.pdf'},
        {'title': 'Needle Cricothyrotomy', 'asset': 'Needle Cricothyrotomy.pdf'},
        {'title': 'EZ IO Procedure', 'asset': 'EZ IO Procedure.pdf'},
        {'title': 'Noninvasive Ventilation', 'asset': 'Noninvasive Ventilation.pdf'},
        {'title': 'Needle Thoracostomy Procedure', 'asset': 'Needle Thoracostomy Procedure.pdf'},
        {'title': 'Supraglottic Airway Management - iGel', 'asset': 'Supraglottic Airway Management - iGel.pdf'},
        {'title': 'Surgical Cricothyrotomy', 'asset': 'Surgical Cricothyrotomy.pdf'},
        {'title': 'Ventilation Procedure', 'asset': 'Ventilation Procedure.pdf'},
      ]
    },
  ];

  late final List<Map<String, String>> rootProtocols;

  @override
  void initState() {
    super.initState();
    _initRootProtocols();
    _loadData();
    if (widget.initialSearch.isNotEmpty) {
      searchQuery = widget.initialSearch;
      _searchController.text = widget.initialSearch;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;

    // Protocols
    final pending = await ProtocolSyncService.instance.pendingProtocols();
    if (pending.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProtocolUpdateDialog(protocols: pending),
      );
    }

    // Deployment orders
    if (!mounted) return;
    final newOrders = await ProtocolSyncService.instance.pendingDeploymentOrders();
    if (newOrders.isNotEmpty && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeploymentOrdersDialog(orders: newOrders),
      );
    }
  }

  void _initRootProtocols() {
    final List<String> allAssets = [
      'Bites.pdf', 'Hazmat.pdf', 'Stings.pdf', 'Stroke.pdf', 'Seizure.pdf', 'Drowning.pdf',
      'Crush Injury.pdf', 'Hypertension.pdf', 'Dead on Scene.pdf', 'EXPANDED SCOPE.pdf',
      'Cyanide Poisoning.pdf', 'Hydrocarbon Fumes.pdf', 'Activated Charcoal.pdf',
      'Behavior Emergency.pdf', 'Adult Resuscitation.pdf', 'Trauma - Antibiotics.pdf',
      'Trauma - Head Injury.pdf', 'Trauma - Neck Trauma.pdf', 'Altered Mental Status.pdf',
      'Trauma - Sexual Assault.pdf', 'Trauma Arrest Guideline.pdf', 'Trauma - Burns - General.pdf',
      'Headache - Expanded Scope.pdf', 'Spinal Motion Restriction.pdf', 'Epistaxis - Expanded Scope.pdf',
      'Toxic Ingestion - Overdose.pdf', 'Chest Pain - Expanded Scope.pdf', 'Firefighter Rehab Guidelines.pdf',
      'GI Bleeding - Expanded Scope.pdf', 'Special Consideration - Rabies.pdf', 'Trauma - Eye Injury - Chemical.pdf',
      'Abdominal Pain - Expanded Scope.pdf', 'Trauma - Blunt - Expanded Scope.pdf', 'Pain Management w expanded scope.pdf',
      'Shock - Medical - Expanded Scope.pdf', 'Trauma - General - Expanded Scope.pdf', 'Vaginal Bleeding - Expanded Scope.pdf',
      'Adult Cardiac Arrest - Initial Care.pdf', 'Diabetic Emergency - Expanded Scope.pdf',
      'Difficulty Breathing - SCAPE or CHF.pdf', 'Electrical Injury and Electrocution.pdf',
      'High Altitude Cerebral Edema - HACE.pdf', 'Dislocations in Austere Environments.pdf',
      'High Altitude Pulmonary Edema - HAPE.pdf', 'Nausea and Vomiting - Expanded Scope.pdf',
      'Trauma - Eye Injury - Expanded Scope.pdf', 'General Medical Care - Expanded Scope.pdf',
      'Trauma - Penetrating - Expanded Scope.pdf', 'Adult Cardiac Arrest - VF-Pulseless VT.pdf',
      'Tranexamic Acid - TXA - Expanded Scope.pdf', 'Adult Cardiac Arrest - PEA and Asystole.pdf',
      'Allergy-Anaphylaxis with expanded scope.pdf', 'Bradycardia with pulse - Expanded Scope.pdf',
      'Acute Mountain Sickness - Expanded Scope.pdf', 'Rabies_postexposure_prophylaxis_algorithm.pdf',
      'Syncope - Weak and Dizzy - Expanded Scope.pdf', 'Airway Obstruction - Foreign Body - Choking.pdf',
      'Difficulty Breathing - Respiratory Distress.pdf', 'Environmental Hyperthermia - Expanded Scope.pdf',
      'Tachycardia - Wide Complex - Expanded Scope.pdf', 'Tachycardia - Narrow Complex - Expanded Scope.pdf',
      'Adult Cardiac Arrest - Additional Treatments to Consider.pdf', 'Difficulty Breathing - Asthma and COPD with expanded scope.pdf',
      'Termination of Resuscitation - Non-traumatic Cardiac Arrest.pdf', 'Adult Cardiac Arrest - Post Resuscitative Care - Expanded Scope.pdf',
      'Rabies World_Health_Organization_post_exposure_rabies_management.pdf'
    ];

    rootProtocols = allAssets.map((asset) => {
      'title': asset.replaceAll('.pdf', ''),
      'asset': asset,
    }).toList();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      favorites = Set.from(prefs.getStringList('favorites') ?? []);
      final uploadsList = prefs.getStringList('user_uploads') ?? [];
      userUploads = uploadsList.where((e) => e.contains('|')).map((e) {
        final parts = e.split('|');
        return {
          'title': parts[0],
          'path': parts[1],
          if (parts.length >= 3) 'category': parts[2],
        };
      }).toList();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', favorites.toList());
  }

  Future<void> _saveUploads() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_uploads', userUploads.map((e) {
      final cat = e['category'] ?? '';
      return '${e['title']}|${e['path']}|$cat';
    }).toList());
  }

  void _toggleFavorite(String assetPath) {
    setState(() {
      if (favorites.contains(assetPath)) {
        favorites.remove(assetPath);
      } else {
        favorites.add(assetPath);
      }
    });
    _saveFavorites();
  }

  static const _kUploadCategories = [
    'Airway', 'Breathing', 'Circulation', 'Trauma', 'Medications', 'Other Protocols',
  ];

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    if (!mounted) return;
    String? category = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to Protocol Folder'),
        children: _kUploadCategories.map((cat) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, cat),
          child: Text(cat),
        )).toList(),
      ),
    );
    if (category == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final uploadDir = Directory('${dir.path}/user_uploads');
    if (!await uploadDir.exists()) await uploadDir.create();

    final targetPath = '${uploadDir.path}/$fileName';
    final targetFile = File(targetPath);
    if (await targetFile.exists()) await targetFile.delete();
    await file.copy(targetPath);

    setState(() {
      userUploads.removeWhere((e) => e['title'] == fileName);
      userUploads.add({'title': fileName, 'path': targetPath, 'category': category});
    });
    _saveUploads();
  }

  Future<void> _deleteUpload(int index) async {
    final file = File(userUploads[index]['path']!);
    if (await file.exists()) await file.delete();
    setState(() {
      final assetPath = userUploads[index]['path']!;
      favorites.remove(assetPath);
      userUploads.removeAt(index);
    });
    _saveUploads();
    _saveFavorites();
  }

  Future<void> _openPdf(String title, String asset, {bool isAsset = true}) async {
    String finalPath;
    if (isAsset) {
      final dir = await getApplicationDocumentsDirectory();
      finalPath = '${dir.path}/$asset';
      final file = File(finalPath);
      if (!await file.exists()) {
        final byteData = await rootBundle.load('assets/protocols/$asset');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }
    } else {
      finalPath = asset;
    }

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(
        title: title,
        filePath: finalPath,
        assetPath: asset,
        isFavorite: favorites.contains(asset),
        onToggleFavorite: () => _toggleFavorite(asset),
      )));
    }
  }

  List<Map<String, dynamic>> get allCategories {
    final airwayItems = <Map<String, dynamic>>[];
    final breathingItems = <Map<String, dynamic>>[];
    final circulationItems = <Map<String, dynamic>>[];
    final traumaItems = <Map<String, dynamic>>[];
    final medicationUploadItems = <Map<String, dynamic>>[];
    final otherItems = <Map<String, dynamic>>[];
    final uncategorizedUploads = <Map<String, dynamic>>[];

    final airwayMeds = <Map<String, dynamic>>[];
    final breathingMeds = <Map<String, dynamic>>[];
    final circulationMeds = <Map<String, dynamic>>[];

    // Route user uploads into the correct folder
    for (final u in userUploads) {
      final uploadItem = {'title': u['title'], 'path': u['path'], 'isUserUpload': true};
      switch (u['category']) {
        case 'Airway':       airwayItems.add(uploadItem); break;
        case 'Breathing':    breathingItems.add(uploadItem); break;
        case 'Circulation':  circulationItems.add(uploadItem); break;
        case 'Trauma':       traumaItems.add(uploadItem); break;
        case 'Medications':  medicationUploadItems.add(uploadItem); break;
        case 'Other Protocols': otherItems.add(uploadItem); break;
        default:             uncategorizedUploads.add(uploadItem);
      }
    }

    final circulationKeywords = ['circulation', 'cardiac', 'heart', 'pulse', 'shock', 'arrest', 'vascular', 'blood', 'vessel'];

    final List<Map<String, dynamic>> pool = [];
    pool.addAll(rootProtocols);
    for (var cat in staticCategories) {
      if (cat['title'] != 'Medications' && cat['title'] != 'Appendix Material') {
        pool.addAll((cat['items'] as List).cast<Map<String, dynamic>>());
      }
    }

    for (var item in pool) {
      final title = item['title'].toString().toLowerCase();
      if (title.contains('trauma')) {
        traumaItems.add(item);
      } else if (title.contains('airway')) {
        airwayItems.add(item);
      } else if (title.contains('breathing')) {
        breathingItems.add(item);
      } else if (circulationKeywords.any((kw) => title.contains(kw))) {
        circulationItems.add(item);
      } else {
        otherItems.add(item);
      }
    }

    final mainMedFolderItems = <Map<String, dynamic>>[];
    final Map<String, List<Map<String, dynamic>>> groupedMeds = {};

    medicationData.forEach((name, data) {
      final item = {'title': name, 'asset': '$name.pdf'};
      final types = (data['types'] as List).cast<String>();
      final abc = (data['abc'] as List).cast<String>();

      if (abc.contains('airway')) airwayMeds.add(item);
      if (abc.contains('breathing')) breathingMeds.add(item);
      if (abc.contains('circulation')) circulationMeds.add(item);

      for (var type in types) {
        groupedMeds.putIfAbsent(type, () => []).add(item);
      }
    });

    groupedMeds.forEach((type, items) {
      mainMedFolderItems.add({
        'title': type,
        'isFolder': true,
        'items': items,
      });
    });

    return [
      if (favorites.isNotEmpty)
        {
          'title': 'Favorites ⭐',
          'isFolder': true,
          'items': _getFavoriteItems(),
          'isFavoriteSection': true,
        },
      if (uncategorizedUploads.isNotEmpty)
        {
          'title': 'User Uploads',
          'isFolder': true,
          'items': uncategorizedUploads,
        },
      {
        'title': 'Airway',
        'isFolder': true,
        'items': [
          ...airwayItems,
          if (airwayMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': airwayMeds},
        ]
      },
      {
        'title': 'Breathing',
        'isFolder': true,
        'items': [
          ...breathingItems,
          if (breathingMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': breathingMeds},
        ]
      },
      {
        'title': 'Circulation',
        'isFolder': true,
        'items': [
          ...circulationItems,
          if (circulationMeds.isNotEmpty) {'title': 'Medications', 'isFolder': true, 'items': circulationMeds},
        ]
      },
      {
        'title': 'Trauma',
        'isFolder': true,
        'items': traumaItems,
      },
      {
        'title': 'Medications',
        'isFolder': true,
        'items': [
          ...mainMedFolderItems,
          if (medicationUploadItems.isNotEmpty)
            {'title': 'Uploaded', 'isFolder': true, 'items': medicationUploadItems},
        ],
      },
      {
        'title': 'Other Protocols',
        'isFolder': true,
        'items': [
          ...otherItems,
          ...staticCategories.where((c) => c['title'] == 'Appendix Material').expand((c) => c['items'] as List),
        ],
      },
    ];
  }

  List<Map<String, dynamic>> _getFavoriteItems() {
    final List<Map<String, dynamic>> items = [];
    for (var upload in userUploads) {
      if (favorites.contains(upload['path'])) {
        items.add({'title': upload['title'], 'path': upload['path'], 'isUserUpload': true});
      }
    }
    for (var item in rootProtocols) {
      if (favorites.contains(item['asset'])) {
        items.add({'title': item['title'], 'asset': item['asset']});
      }
    }
    for (final name in medicationData.keys) {
      final asset = '$name.pdf';
      if (favorites.contains(asset)) {
        items.add({'title': name, 'asset': asset});
      }
    }
    for (var cat in staticCategories) {
      for (var item in cat['items']) {
        if (favorites.contains(item['asset'])) {
          items.add({'title': item['title'], 'asset': item['asset']});
        }
      }
    }
    return items;
  }

  List<Map<String, dynamic>> get filteredItems {
    if (searchQuery.isEmpty) return [];
    final query = searchQuery.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (var item in rootProtocols) {
      if (item['title']!.toLowerCase().contains(query)) results.add(item);
    }
    for (var name in medicationData.keys) {
      if (name.toLowerCase().contains(query)) results.add({'title': name, 'asset': '$name.pdf'});
    }
    for (var cat in staticCategories) {
      for (var item in cat['items']) {
        if (item['title']!.toLowerCase().contains(query)) results.add(item);
      }
    }
    for (var upload in userUploads) {
      if (upload['title']!.toLowerCase().contains(query)) {
        results.add({'title': upload['title'], 'path': upload['path'], 'isUserUpload': true});
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = searchQuery.isNotEmpty;
    final categoriesToShow = allCategories;

    return Scaffold(
      // ── Drawer now holds the protocol list ───────────────────────────────
      drawer: widget.protocolsOnly ? null : Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.menu_book, color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text('Protocols', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('v$kCurrentVersion', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search protocols…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.light
                      ? Colors.grey[100]
                      : Colors.grey[800],
                ),
                onChanged: (value) => setState(() => searchQuery = value),
              ),
            ),
            Expanded(
              child: isSearching
                  ? ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final isUser = item['isUserUpload'] == true;
                        final assetPath = isUser ? (item['path'] ?? '') : (item['asset'] ?? '');
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                          title: Text(item['title'] ?? 'Unknown', style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            Navigator.pop(context);
                            _openPdf(item['title'] ?? 'Unknown', assetPath, isAsset: !isUser);
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: categoriesToShow.length,
                      itemBuilder: (context, index) =>
                          _buildCategoryTile(categoriesToShow[index]),
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import PDF'),
              onTap: () { Navigator.pop(context); _uploadFile(); },
            ),
            if (widget.onLogout != null)
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Log Out', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(context); widget.onLogout!(); },
              ),
          ],
        ),
      ),

      // ── AppBar ───────────────────────────────────────────────────────────
      appBar: AppBar(
        title: Text(widget.protocolsOnly ? 'Protocols' : 'ResQruck'),
        actions: [
          IconButton(icon: const Icon(Icons.brightness_medium), onPressed: widget.onThemeToggle),
        ],
      ),

      // ── Body ─────────────────────────────────────────────────────────────
      body: widget.protocolsOnly
          ? _buildProtocolBrowser()
          : _buildHomeLauncher(context),
    );
  }

  Widget _buildProtocolBrowser() {
    final isSearching = searchQuery.isNotEmpty;
    final categories = allCategories;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search protocols…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() {
                      searchQuery = '';
                      _searchController.clear();
                    }))
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            filled: true,
          ),
          onChanged: (v) => setState(() => searchQuery = v),
        ),
      ),
      Expanded(
        child: isSearching
            ? ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (_, i) {
                  final item = filteredItems[i];
                  final isUser = item['isUserUpload'] == true;
                  final assetPath = isUser ? (item['path'] ?? '') : (item['asset'] ?? '');
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                    title: Text(item['title'] ?? 'Unknown', style: const TextStyle(fontSize: 14)),
                    onTap: () => _openPdf(item['title'] ?? 'Unknown', assetPath, isAsset: !isUser),
                  );
                },
              )
            : ListView.builder(
                itemCount: categories.length,
                itemBuilder: (_, i) => _buildCategoryTile(categories[i]),
              ),
      ),
    ]);
  }

  Widget _buildHomeLauncher(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _launcherSection('Clinical Tools'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.account_tree, 'Decision Trees', Colors.indigo, DecisionTreeScreen()),
          _FeatureTile(Icons.medication, 'Drug & Dosing', Colors.teal, DrugDosingScreen()),
          _FeatureTile(Icons.checklist, 'Procedure\nChecklists', Colors.green, ProcedureListScreen()),
          _FeatureTile(Icons.biotech, 'Differential\nDiagnosis', Colors.purple, DifferentialDxScreen()),
          _FeatureTile(Icons.assignment_outlined, 'Patient\nReports', Colors.red, PatientReportListScreen()),
          _FeatureTile(Icons.workspace_premium, 'Cert\nVault', Colors.deepPurple, CertVaultScreen()),
          _FeatureTile(Icons.terrain, 'Field\nGuide', Color(0xFF4E6B3A), BackcountryGuideScreen()),
          _FeatureTile(Icons.checklist_rtl, 'Pre-Deploy\nChecklist', Color(0xFF0277BD), RemsChecklistScreen()),
        ]),
        _launcherSection('Team Coordination'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.account_tree_outlined, 'Team\nCommand', Colors.indigo, TeamCommandScreen()),
          _FeatureTile(Icons.emergency, 'MCI\nTriage', Colors.red, MciTriageScreen()),
          _FeatureTile(Icons.radar, 'Tac\nMap', Colors.teal, TacMapScreen()),
          _FeatureTile(Icons.description_outlined, 'Team\nProtocols', Colors.deepOrange, TeamProtocolsScreen()),
        ]),
        _launcherSection('Reference'),
        _launcherGrid(context, const [
          _FeatureTile(Icons.info_outline, 'Protocol\nVersion', Colors.blueGrey, ProtocolVersionScreen()),
        ]),
      ],
    );
  }

  Widget _launcherSection(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _launcherGrid(BuildContext context, List<_FeatureTile> tiles) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) {
        final t = tiles[i];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => t.screen)),
          child: Container(
            decoration: BoxDecoration(
              color: t.color.withValues(alpha: 0.12),
              border: Border.all(color: t.color.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(t.icon, color: t.color, size: 32),
                const SizedBox(height: 6),
                Text(t.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.color, height: 1.2)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> category, {double depth = 0}) {
    if (category['isFolder'] == true) {
      return ExpansionTile(
        initiallyExpanded: category['isFavoriteSection'] == true,
        title: Text(
          category['title'],
          style: TextStyle(
            fontWeight: depth == 0 ? FontWeight.bold : FontWeight.normal,
            fontSize: depth == 0 ? 18 : 16,
          ),
        ),
        children: (category['items'] as List).map<Widget>((item) {
          if (item['isFolder'] == true) {
            return Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildCategoryTile(item, depth: depth + 1),
            );
          } else {
            return _buildFileTile(item);
          }
        }).toList(),
      );
    } else {
      return _buildFileTile(category);
    }
  }

  Widget _buildFileTile(Map<String, dynamic> item) {
    final isUser = item['isUserUpload'] == true;
    final assetPath = isUser ? (item['path'] ?? '') : (item['asset'] ?? '');
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
      title: Text(item['title'] ?? 'Unknown'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUser)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.grey),
              onPressed: () {
                final idx = userUploads.indexWhere((u) => u['path'] == item['path']);
                if (idx != -1) _deleteUpload(idx);
              },
            ),
          IconButton(
            icon: Icon(favorites.contains(assetPath) ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () => _toggleFavorite(assetPath),
          ),
        ],
      ),
      onTap: () => _openPdf(item['title'] ?? 'Unknown', assetPath, isAsset: !isUser),
    );
  }
}

class _FeatureTile {
  final IconData icon;
  final String label;
  final Color color;
  final Widget screen;
  const _FeatureTile(this.icon, this.label, this.color, this.screen);
}

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String filePath;
  final String assetPath;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.filePath,
    required this.assetPath,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              widget.onToggleFavorite();
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => File(widget.filePath).readAsBytes(),
        allowSharing: false,
        allowPrinting: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}


class _DeploymentOrdersDialog extends StatefulWidget {
  final List<DeploymentOrder> orders;
  const _DeploymentOrdersDialog({required this.orders});

  @override
  State<_DeploymentOrdersDialog> createState() => _DeploymentOrdersDialogState();
}

class _DeploymentOrdersDialogState extends State<_DeploymentOrdersDialog> {
  bool _acknowledging = false;

  Future<void> _ackAll() async {
    setState(() => _acknowledging = true);
    for (final o in widget.orders) {
      await ProtocolSyncService.instance.markDeploymentOrderViewed(o.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.orders.length;
    return AlertDialog(
      icon: const Icon(Icons.assignment_outlined, color: Colors.orange, size: 32),
      title: Text('$n Deployment Order${n > 1 ? 's' : ''} Received'),
      content: SizedBox(
        width: double.maxFinite,
        height: 260,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'The following order${n > 1 ? 's have' : ' has'} been issued. '
            'Tap to review each one.',
            style: TextStyle(fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: n,
              itemBuilder: (_, i) {
                final o = widget.orders[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(Icons.assignment_outlined,
                        color: Colors.orange, size: 24),
                    title: Text(o.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                      'From: ${o.uploadedBy.isEmpty ? 'Admin' : o.uploadedBy}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: _acknowledging ? null : _ackAll,
          icon: _acknowledging
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Acknowledge'),
        ),
      ],
    );
  }
}
