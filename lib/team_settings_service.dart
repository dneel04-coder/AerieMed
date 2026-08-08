import 'protocol_admin.dart' show SupabaseService;

/// Simple team-wide key/value settings — currently the two shared team
/// drive links patient reports can be sent to. Unlike admin credentials
/// (per-device, in SharedPreferences), this is meant to be the same for
/// every device, so it lives in Supabase instead.
class TeamSettingsService {
  static const _teamDriveLinkKeys = ['team_drive_link_1', 'team_drive_link_2'];

  /// Both configured team drive links, in order. Empty string for any slot
  /// that isn't set.
  static Future<List<String>> getTeamDriveLinks() async {
    await SupabaseService.ensureInitialized();
    final client = SupabaseService.client;
    if (client == null) return const ['', ''];
    try {
      final rows = await client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', _teamDriveLinkKeys);
      final byKey = {for (final r in rows as List) r['key'] as String: r['value'] as String? ?? ''};
      return _teamDriveLinkKeys.map((k) => byKey[k] ?? '').toList();
    } catch (e) {
      throw Exception('Could not load team drive links: $e');
    }
  }

  /// Sets both links in one call (empty string clears a slot).
  static Future<void> setTeamDriveLinks(String link1, String link2) async {
    await SupabaseService.ensureInitialized();
    final client = SupabaseService.client;
    if (client == null) throw Exception('Not connected to Supabase');
    await client.from('app_settings').upsert([
      {'key': _teamDriveLinkKeys[0], 'value': link1},
      {'key': _teamDriveLinkKeys[1], 'value': link2},
    ]);
  }
}
