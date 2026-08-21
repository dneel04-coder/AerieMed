import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'protocol_admin.dart' show SupabaseService;
import 'push_notification_service.dart';

const List<String> kCertLevels = ['Paramedic', 'AEMT', 'EMT', 'None'];

class UserProfile {
  static const _kName            = 'profile_name';
  static const _kCallsign        = 'profile_callsign';
  static const _kCertLevel       = 'profile_cert_level';
  static const _kRt130           = 'profile_rt130';
  static const _kRopeRescue      = 'profile_rope_rescue';
  static const _kLoggedIn        = 'profile_logged_in';
  static const _kUserId          = 'tac_user_id';
  static const _kAccessValidated   = 'profile_access_validated';
  static const _kPurchaseUnlocked  = 'profile_purchase_unlocked';

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

  static Future<bool> isAccessValidated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAccessValidated) ?? false;
  }

  static Future<void> markAccessValidated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAccessValidated, true);
  }

  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kPurchaseUnlocked) ?? false;
  }

  static Future<void> markUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPurchaseUnlocked, true);
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

  /// Returns true if another profile (different user_id) already uses this
  /// callsign. Case-insensitive, matching how callsigns are compared
  /// elsewhere (map markers, calendar cleanup).
  static Future<bool> callsignTaken(String callsign, {required String excludeUserId}) async {
    final client = SupabaseService.client;
    if (client == null || callsign.isEmpty) return false;
    try {
      final rows = await client
          .from('user_profiles')
          .select('user_id')
          .ilike('callsign', callsign)
          .neq('user_id', excludeUserId)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Looks up the existing profile for [callsign], if any — used when a
  /// reinstall's freshly-generated device id collides with a callsign
  /// that's already registered, so the app can offer to restore that
  /// profile instead of just blocking the user.
  static Future<UserProfile?> fetchByCallsign(String callsign) async {
    final client = SupabaseService.client;
    if (client == null || callsign.isEmpty) return null;
    try {
      final rows = await client
          .from('user_profiles')
          .select('user_id, name, callsign, cert_level, rt130, rope_rescue')
          .ilike('callsign', callsign)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      final r = rows.first;
      return UserProfile(
        userId: r['user_id'] as String,
        name: r['name'] as String? ?? '',
        callsign: r['callsign'] as String? ?? '',
        certLevel: r['cert_level'] as String? ?? 'None',
        rt130: r['rt130'] as bool? ?? false,
        ropeRescue: r['rope_rescue'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Replaces this device's local random id with [userId] — used after
  /// restoring an existing profile post-reinstall, so this device's saves
  /// update that same `user_profiles` row (matching on `user_id` primary
  /// key) instead of colliding with it as a would-be duplicate.
  static Future<void> adoptUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserId, userId);
  }

  /// Status of this device's self-serve access request, if any:
  /// 'pending' | 'approved' | 'denied' | null (no request submitted — the
  /// access-code fast path is unaffected by any of this).
  static Future<String?> fetchAccessRequestStatus(String userId) async {
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) return null;
    try {
      final rows = await SupabaseService.client!
          .from('access_requests')
          .select('status')
          .eq('user_id', userId)
          .limit(1);
      return (rows as List).isEmpty ? null : rows.first['status'] as String;
    } catch (_) {
      return null;
    }
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
  late final TextEditingController _codeCtrl;
  String _certLevel = 'None';
  bool _rt130 = false;
  bool _ropeRescue = false;
  bool _stayLoggedIn = true;
  bool _saving = false;
  bool _accessValidated = false;
  UserProfile? _existing;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _callsignCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final results = await Future.wait([
      UserProfile.load(),
      UserProfile.isAccessValidated(),
    ]);
    final p = results[0] as UserProfile;
    final validated = results[1] as bool;
    if (!mounted) return;
    setState(() {
      _existing = p;
      _nameCtrl.text = p.name;
      _callsignCtrl.text = p.callsign;
      _certLevel = p.certLevel;
      _rt130 = p.rt130;
      _ropeRescue = p.ropeRescue;
      _accessValidated = validated;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Full name is required.')));
      return;
    }
    final callsign = _callsignCtrl.text.trim();
    if (callsign.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Callsign is required.')));
      return;
    }
    setState(() => _saving = true);

    final ok0 = await SupabaseService.ensureInitialized();
    if (ok0) {
      final taken = await UserProfile.callsignTaken(
          callsign, excludeUserId: _existing?.userId ?? '');
      if (taken) {
        final existingProfile = await UserProfile.fetchByCallsign(callsign);
        if (!mounted) return;
        if (existingProfile == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('A profile with that callsign already exists.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4)));
          setState(() => _saving = false);
          return;
        }
        final restore = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Profile Already Exists'),
            content: Text(
                'A profile for "${existingProfile.name}" already uses callsign '
                '"${existingProfile.callsign}". If this is you reinstalling the '
                'app, restore that profile instead of creating a new one.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Use a different callsign')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('This is me — restore')),
            ],
          ),
        );
        if (restore != true || !mounted) return;
        await UserProfile.adoptUserId(existingProfile.userId);
        setState(() {
          _existing = existingProfile;
          _nameCtrl.text = existingProfile.name;
          _callsignCtrl.text = existingProfile.callsign;
          _certLevel = existingProfile.certLevel;
          _rt130 = existingProfile.rt130;
          _ropeRescue = existingProfile.ropeRescue;
        });
      }
    }
    if (!mounted) return;

    // Validate access code on first login.
    if (!_accessValidated) {
      final code = _codeCtrl.text.trim().toUpperCase();
      if (code.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Access code is required.')));
        setState(() => _saving = false);
        return;
      }
      final ok = await SupabaseService.ensureInitialized();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot reach server to validate access code. Check your connection.'),
            backgroundColor: Colors.red));
        setState(() => _saving = false);
        return;
      }
      final client = SupabaseService.client!;
      final rows = await client
          .from('app_access_codes')
          .select('id, bypass_paywall')
          .eq('code', code)
          .eq('is_active', true)
          .limit(1);
      if (!mounted) return;
      if ((rows as List).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Invalid or inactive access code.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4)));
        setState(() => _saving = false);
        return;
      }
      final bypass = (rows.first['bypass_paywall'] as bool?) ?? false;
      // Notify admin of the new user.
      final callsign = _callsignCtrl.text.trim();
      try {
        await client.from('admin_alerts').insert({
          'type': 'access',
          'title': 'New User: $name',
          'callsign': callsign.isNotEmpty ? callsign : name,
          'body': 'User $name${callsign.isNotEmpty ? ' ($callsign)' : ''} '
              'joined using access code $code',
        });
      } catch (_) {}
      await UserProfile.markAccessValidated();
      // Apple Guideline 3.1.1: on iOS, paid content must unlock only through
      // StoreKit — an access code (even one entered here at login, not on
      // the paywall itself) must never be able to bypass payment.
      if (bypass && !Platform.isIOS) await UserProfile.markUnlocked();
      setState(() => _accessValidated = true);
    }

    final profile = UserProfile(
      userId: _existing?.userId ?? '',
      name: _nameCtrl.text.trim(),
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
    _codeCtrl.dispose();
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
                labelText: 'Callsign *',
                hintText: 'Must be unique — no one else can use this',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.radio),
              ),
            ),
            const SizedBox(height: 14),

            // Access code — required on first login only
            if (!_accessValidated) ...[
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Access Code *',
                  hintText: 'Contact your administrator for a code',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  filled: true,
                  fillColor: cs.primaryContainer.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A one-time access code is required to activate your account.',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () async {
                    final profile = _existing ?? await UserProfile.load();
                    if (!mounted) return;
                    await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => RequestAccessScreen(
                              userId: profile.userId,
                              nameHint: _nameCtrl.text.trim(),
                              callsignHint: _callsignCtrl.text.trim(),
                              onApproved: () => setState(() => _accessValidated = true),
                            )));
                  },
                  child: const Text("Don't have a code? Request Access"),
                ),
              ),
              const SizedBox(height: 14),
            ],

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

/// Self-serve alternative to an admin-issued access code: submit name/
/// callsign/company/email for review instead. Nothing about the purchase
/// flow is reachable until an admin approves the request (see
/// AccessPendingScreen and the access_requests schema/triggers).
class RequestAccessScreen extends StatefulWidget {
  final String userId;
  final String nameHint;
  final String callsignHint;
  final VoidCallback onApproved;
  const RequestAccessScreen({
    super.key,
    required this.userId,
    required this.onApproved,
    this.nameHint = '',
    this.callsignHint = '',
  });

  @override
  State<RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends State<RequestAccessScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _callsignCtrl;
  final _companyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.nameHint);
    _callsignCtrl = TextEditingController(text: widget.callsignHint);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _callsignCtrl.dispose();
    _companyCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Full name is required.')));
      return;
    }
    setState(() => _submitting = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot reach server. Check your connection.'),
          backgroundColor: Colors.red));
      setState(() => _submitting = false);
      return;
    }
    try {
      await SupabaseService.client!.from('access_requests').insert({
        'user_id': widget.userId,
        'name': name,
        'callsign': _callsignCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      });
      // Register this device for a push notification the moment an admin
      // decides, before login/purchase even exist for this user yet.
      await PushNotificationService.instance.initialize(widget.userId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not submit request: $e'), backgroundColor: Colors.red));
        setState(() => _submitting = false);
      }
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => AccessPendingScreen(userId: widget.userId, onApproved: widget.onApproved)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Access')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              "Tell us who you are and we'll review your request. "
              "You'll be notified as soon as it's approved.",
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Full Name *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _callsignCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Callsign', border: OutlineInputBorder(), prefixIcon: Icon(Icons.radio)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _companyCtrl,
              decoration: const InputDecoration(
                  labelText: 'Company / Affiliation',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email (optional, for follow-up)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined)),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Request'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Shown while a self-serve access request is pending, and again on relaunch
/// (see main.dart) until it's decided. Denied requests stay here with no
/// path forward to login/paywall; approved ones hand control back to
/// LoginScreen via onApproved.
class AccessPendingScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onApproved;
  const AccessPendingScreen({super.key, required this.userId, required this.onApproved});

  @override
  State<AccessPendingScreen> createState() => _AccessPendingScreenState();
}

class _AccessPendingScreenState extends State<AccessPendingScreen> {
  bool _checking = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final status = await UserProfile.fetchAccessRequestStatus(widget.userId);
    if (!mounted) return;
    setState(() { _status = status; _checking = false; });
    if (status == 'approved') {
      await UserProfile.markAccessValidated();
      if (!mounted) return;
      widget.onApproved();
      // When pushed from RequestAccessScreen this reveals LoginScreen
      // underneath; when used as main.dart's root widget there's nothing to
      // pop — onApproved() alone makes the parent swap away from this screen.
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final denied = _status == 'denied';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(denied ? Icons.block : Icons.hourglass_top,
                  size: 72, color: denied ? Colors.red : Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                denied ? 'Access Request Not Approved' : 'Access Request Pending',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                denied
                    ? "Your request wasn't approved. Contact the administrator if you think this is a mistake."
                    : "We'll send you a notification as soon as it's reviewed. You can also check back here.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('Check Again'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
