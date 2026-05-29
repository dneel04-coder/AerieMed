import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService;

const List<String> kCertLevels = ['Paramedic', 'AEMT', 'EMT', 'None'];

class UserProfile {
  static const _kName       = 'profile_name';
  static const _kCallsign   = 'profile_callsign';
  static const _kCertLevel  = 'profile_cert_level';
  static const _kRt130      = 'profile_rt130';
  static const _kRopeRescue = 'profile_rope_rescue';
  static const _kLoggedIn   = 'profile_logged_in';
  static const _kUserId     = 'tac_user_id';

  final String userId;
  String name;
  String callsign;
  String certLevel;
  bool rt130;
  bool ropeRescue;

  UserProfile({
    required this.userId,
    this.name = '',
    this.callsign = '',
    this.certLevel = 'None',
    this.rt130 = false,
    this.ropeRescue = false,
  });

  String get displayCallsign => callsign.isNotEmpty ? callsign : name;

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLoggedIn) ?? false;
  }

  static Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString(_kUserId) ?? '';
    if (userId.isEmpty) {
      final rng = Random.secure();
      userId = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_kUserId, userId);
    }
    return UserProfile(
      userId: userId,
      name: prefs.getString(_kName) ?? '',
      callsign: prefs.getString(_kCallsign) ?? '',
      certLevel: prefs.getString(_kCertLevel) ?? 'None',
      rt130: prefs.getBool(_kRt130) ?? false,
      ropeRescue: prefs.getBool(_kRopeRescue) ?? false,
    );
  }

  Future<void> save({bool stayLoggedIn = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name);
    await prefs.setString(_kCallsign, callsign);
    await prefs.setString(_kCertLevel, certLevel);
    await prefs.setBool(_kRt130, rt130);
    await prefs.setBool(_kRopeRescue, ropeRescue);
    if (stayLoggedIn) await prefs.setBool(_kLoggedIn, true);
    // Keep tac_callsign in sync — used by Tac Map, calendar, and cert uploads.
    await prefs.setString('tac_callsign', displayCallsign);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLoggedIn, false);
  }

  Future<void> syncToSupabase() async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('user_profiles').upsert({
        'user_id': userId,
        'name': name,
        'callsign': displayCallsign,
        'cert_level': certLevel,
        'rt130': rt130,
        'rope_rescue': ropeRescue,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }
}


class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _callsignCtrl;
  String _certLevel = 'None';
  bool _rt130 = false;
  bool _ropeRescue = false;
  bool _stayLoggedIn = true;
  bool _saving = false;
  UserProfile? _existing;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _callsignCtrl = TextEditingController();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final p = await UserProfile.load();
    if (!mounted) return;
    setState(() {
      _existing = p;
      _nameCtrl.text = p.name;
      _callsignCtrl.text = p.callsign;
      _certLevel = p.certLevel;
      _rt130 = p.rt130;
      _ropeRescue = p.ropeRescue;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Full name is required.')));
      return;
    }
    setState(() => _saving = true);

    final profile = UserProfile(
      userId: _existing?.userId ?? '',
      name: name,
      callsign: _callsignCtrl.text.trim(),
      certLevel: _certLevel,
      rt130: _rt130,
      ropeRescue: _ropeRescue,
    );
    await profile.save(stayLoggedIn: _stayLoggedIn);

    // Best-effort Supabase sync — silent if not yet configured.
    await SupabaseService.ensureInitialized();
    await profile.syncToSupabase();

    if (mounted) widget.onLoggedIn();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _callsignCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.medical_services_outlined, size: 72, color: cs.primary),
            const SizedBox(height: 10),
            Text('ResQruck', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Enter your profile to continue',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 32),

            // Name
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),

            // Callsign
            TextField(
              controller: _callsignCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Callsign',
                hintText: 'Leave blank to use your name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.radio),
              ),
            ),
            const SizedBox(height: 14),

            // Cert level
            DropdownButtonFormField<String>(
              value: _certLevel,
              decoration: const InputDecoration(
                labelText: 'Certification Level',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.workspace_premium),
              ),
              items: kCertLevels
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) { if (v != null) setState(() => _certLevel = v); },
            ),
            const SizedBox(height: 14),

            // Checkboxes
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                CheckboxListTile(
                  value: _rt130,
                  onChanged: (v) => setState(() => _rt130 = v ?? false),
                  title: const Text('RT-130 Certified'),
                  secondary: const Icon(Icons.local_fire_department),
                  dense: true,
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  value: _ropeRescue,
                  onChanged: (v) => setState(() => _ropeRescue = v ?? false),
                  title: const Text('Rope Rescue Technician'),
                  secondary: const Icon(Icons.safety_divider),
                  dense: true,
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // Stay logged in
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: _stayLoggedIn,
                onChanged: (v) => setState(() => _stayLoggedIn = v),
                title: const Text('Stay Logged In'),
                subtitle: const Text('Skip this screen on future launches'),
                dense: true,
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue'),
            ),
          ]),
        ),
      ),
    );
  }
}
