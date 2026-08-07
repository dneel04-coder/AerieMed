import 'protocol_admin.dart' show SupabaseService;

/// Simple team-wide key/value settings — currently just the shared team
/// drive link patient reports can be sent to. Unlike admin credentials
/// (per-device, in SharedPreferences), this is meant to be the same for
/// every device, so it lives in Supabase instead.
class TeamSettingsService {
  static const _teamDriveLinkKey = 'team_drive_link';

  static Future<String> getTeamDriveLink() async {
    await SupabaseService.ensureInitialized();
    final client = SupabaseService.client;
    if (client == null) return '';
    try {
      final rows = await client
          .from('app_settings')
          .select('value')
          .eq('key', _teamDriveLinkKey)
          .limit(1);
      if ((rows as List).isEmpty) return '';
      return rows.first['value'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> setTeamDriveLink(String link) async {
    await SupabaseService.ensureInitialized();
    final client = SupabaseService.client;
    if (client == null) return;
    await client.from('app_settings').upsert({'key': _teamDriveLinkKey, 'value': link});
  }
}
