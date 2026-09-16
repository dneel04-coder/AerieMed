import 'package:flutter/material.dart';
import '../protocol_admin.dart' show SupabaseService;

/// Shared by the Windows Command Console (main_admin.dart) and the web
/// Admin Portal (main_portal.dart) -- same Supabase project, same
/// user_profiles.role/org_id, same access boundary either way: only
/// org_admin/super_admin get in, looked up from the signed-in account
/// itself, never from anything the client claims.
class ConsoleSession {
  final bool authed;
  final String role;
  final String? orgId;
  final String orgName;
  const ConsoleSession({required this.authed, required this.role, required this.orgId, required this.orgName});

  static const signedOut = ConsoleSession(authed: false, role: 'member', orgId: null, orgName: '');
}

/// Looks up the given auth user id's own role/org. Returns a denied
/// (authed: false) session for anyone who isn't org_admin/super_admin --
/// callers should sign the client back out when that happens, same as if
/// they'd never signed in.
Future<ConsoleSession> resolveConsoleSession(String authUserId) async {
  final client = SupabaseService.client;
  if (client == null) return ConsoleSession.signedOut;
  try {
    final row = await client
        .from('user_profiles')
        .select('role, org_id, organizations(name)')
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    final role = row?['role'] as String? ?? 'member';
    if (role != 'org_admin' && role != 'super_admin') return ConsoleSession.signedOut;
    final orgId = row?['org_id'] as String?;
    // A super_admin oversees every organization, so their own nominal org
    // (usually the Legacy/Unassigned bucket) isn't meaningful to show.
    final orgName = role == 'super_admin' ? '' : ((row?['organizations'] as Map?)?['name'] as String? ?? '');
    return ConsoleSession(authed: true, role: role, orgId: orgId, orgName: orgName);
  } catch (_) {
    return ConsoleSession.signedOut;
  }
}

/// Restores a session supabase_flutter already persisted (secure local
/// storage on desktop, browser storage on web) -- if there's a current
/// session, resolve it; if not, nothing to do.
Future<ConsoleSession> restoreConsoleSession() async {
  final session = SupabaseService.client?.auth.currentSession;
  if (session == null) return ConsoleSession.signedOut;
  return resolveConsoleSession(session.user.id);
}

/// Shared sign-in screen -- [appName]/[tagline] are the only visual
/// difference between the desktop Console and the web Admin Portal.
class ConsoleSignInScreen extends StatefulWidget {
  final String appName;
  final String tagline;
  final void Function(ConsoleSession session) onSignedIn;
  const ConsoleSignInScreen({
    super.key,
    required this.onSignedIn,
    this.appName = 'ResQruck Command Console',
    this.tagline = 'Sign in with your organization admin account',
  });

  @override
  State<ConsoleSignInScreen> createState() => _ConsoleSignInScreenState();
}

class _ConsoleSignInScreenState extends State<ConsoleSignInScreen> {
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
      final session = await resolveConsoleSession(userId);
      if (!session.authed) {
        await client.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Access denied — ask your organization admin for access.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5)));
          setState(() => _signingIn = false);
        }
        return;
      }
      widget.onSignedIn(session);
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
            Text(widget.appName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.tagline,
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onSubmitted: (_) => _signIn(),
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
