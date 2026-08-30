import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'patient_report.dart';
import 'asset_service.dart' show AssetService, Team;


class SupabaseService {
  static const _urlKey = 'tac_supabase_url';
  static const _anonKey = 'tac_supabase_anon_key';
  static const _kDefaultUrl = 'https://vlgiclyuxaleyusalexo.supabase.co';
  static const _kDefaultKey = 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';
  static bool _initialized = false;
  static bool _migrated = false;

  /// Clears initialized state so ensureInitialized re-runs with new credentials.
  static void reset() { _initialized = false; _migrated = false; }

  // Strip any path/query from the URL — Supabase needs only the bare host.
  static String _cleanUrl(String raw) {
    try {
      final u = Uri.parse(raw.trim());
      return '${u.scheme}://${u.host}';
    } catch (_) { return raw; }
  }

  static Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    final prefs = await SharedPreferences.getInstance();
    final rawUrl = prefs.getString(_urlKey)?.isNotEmpty == true
        ? prefs.getString(_urlKey)!
        : _kDefaultUrl;
    final url = _cleanUrl(rawUrl);
    final key = prefs.getString(_anonKey)?.isNotEmpty == true
        ? prefs.getString(_anonKey)!
        : _kDefaultKey;
    try {
      await Supabase.initialize(url: url, anonKey: key);
      _initialized = true;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('already') || msg.contains('initialized')) {
        _initialized = true;
      } else {
        return false;
      }
    }
    await _runMigrations();
    return true;
  }

  static Future<void> _runMigrations() async {
    if (_migrated) return;
    _migrated = true;
    final client = Supabase.instance.client;
    // Call the SECURITY DEFINER RPC that creates all missing tables/columns.
    // If the function doesn't exist yet (admin hasn't run setup SQL), this
    // fails silently — features degrade gracefully until the SQL is run once.
    try { await client.rpc('resqruck_auto_migrate'); } catch (_) {}
    // Probe expiration_date so cert sync can skip it if absent.
    try {
      await client.from('team_certs').select('expiration_date').limit(1);
      hasExpirationCol = true;
    } catch (_) {
      hasExpirationCol = false;
    }
  }

  static bool hasExpirationCol = true;

  static SupabaseClient? get client => _initialized ? Supabase.instance.client : null;
}


class ProtocolEntry {
  final String id;
  final String name;
  final int version;
  final String filePath;
  final bool isActive;
  final DateTime updatedAt;
  final String updatedBy;
  final String notes;
  // Null = broadcast to everyone (existing/default behavior, unchanged).
  // Non-null targetUserIds = only these user_ids should see this protocol.
  // Non-null targetTeamId = only users on that team should see it. Both may
  // be set independently; a user sees the protocol if either matches.
  final List<String>? targetUserIds;
  final String? targetTeamId;
  // 'medical' feeds the home screen's "Protocols" card (medical-director
  // authorized content); 'team' feeds "Team Protocols" (team-specific,
  // non-medical directions).
  final String category;

  const ProtocolEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.filePath,
    required this.isActive,
    required this.updatedAt,
    required this.updatedBy,
    required this.notes,
    this.targetUserIds,
    this.targetTeamId,
    this.category = 'medical',
  });

  factory ProtocolEntry.fromMap(Map<String, dynamic> m) => ProtocolEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        version: (m['version'] as num?)?.toInt() ?? 1,
        filePath: m['file_path'] as String,
        isActive: m['is_active'] as bool? ?? true,
        updatedAt: DateTime.tryParse(m['updated_at'] as String? ?? '') ?? DateTime.now(),
        updatedBy: m['updated_by'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        targetUserIds: (m['target_user_ids'] as List?)?.cast<String>(),
        targetTeamId: m['target_team_id'] as String?,
        category: m['category'] as String? ?? 'medical',
      );

  String get localCacheName => '${id}_v$version.pdf';
}


class ProtocolSyncService {
  static final instance = ProtocolSyncService._();
  ProtocolSyncService._();

  static const _adminModeKey = 'proto_admin_mode';
  static const _adminUsernameKey = 'proto_admin_username';
  static const _adminPasswordKey = 'proto_admin_password';
  static const _userIdKey = 'tac_user_id';
  static const _callsignKey = 'tac_callsign';
  static const _defaultUsername = 't2ops';
  static const _defaultPassword = 'Lucas22!';

  Future<bool> get isAdminMode async =>
      (await SharedPreferences.getInstance()).getBool(_adminModeKey) ?? false;

  Future<void> setAdminMode(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_adminModeKey, value);

  Future<String> getAdminUsername() async =>
      (await SharedPreferences.getInstance()).getString(_adminUsernameKey) ?? _defaultUsername;

  Future<String> getAdminPassword() async =>
      (await SharedPreferences.getInstance()).getString(_adminPasswordKey) ?? _defaultPassword;

  Future<void> setAdminCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminUsernameKey, username);
    await prefs.setString(_adminPasswordKey, password);
  }

  Future<String> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_userIdKey);
    if (id == null) {
      final rng = Random.secure();
      id = List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString(_userIdKey, id);
    }
    return id;
  }

  Future<String> _callsign() async =>
      (await SharedPreferences.getInstance()).getString(_callsignKey) ?? 'Unknown';

  Future<SupabaseClient?> _client() async {
    await SupabaseService.ensureInitialized();
    return SupabaseService.client;
  }

  String _newUuid() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<List<ProtocolEntry>> pendingProtocols({String? category}) async {
    final client = await _client();
    if (client == null) return [];
    try {
      final userId = await _userId();
      final protocols = await myVisibleProtocols(category: category);
      final ackedIds = (await client
              .from('protocol_acknowledgments')
              .select('protocol_id')
              .eq('user_id', userId) as List)
          .map((a) => a['protocol_id'] as String)
          .toSet();
      return protocols.where((p) => !ackedIds.contains(p.id)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<ProtocolEntry>> activeProtocols({String? category}) async {
    final client = await _client();
    if (client == null) return [];
    try {
      var query = client.from('protocols').select().eq('is_active', true);
      if (category != null) query = query.eq('category', category);
      return (await query.order('name') as List)
          .map((r) => ProtocolEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Active protocols visible to this device: untargeted (broadcast, the
  /// existing default) plus anything targeted at this user_id or this
  /// user's team_id specifically -- same client-side-filter shape already
  /// used for deployment_orders' targetUserIds. Optionally scoped to just
  /// 'medical' or 'team' protocols.
  Future<List<ProtocolEntry>> myVisibleProtocols({String? category}) async {
    final all = await activeProtocols(category: category);
    final client = await _client();
    if (client == null) return all;
    final userId = await _userId();
    String? myTeamId;
    try {
      final row = await client
          .from('user_profiles')
          .select('team_id')
          .eq('user_id', userId)
          .maybeSingle();
      myTeamId = row?['team_id'] as String?;
    } catch (_) {}
    return all.where((p) {
      if (p.targetUserIds == null && p.targetTeamId == null) return true;
      if (p.targetUserIds?.contains(userId) == true) return true;
      if (myTeamId != null && p.targetTeamId == myTeamId) return true;
      return false;
    }).toList();
  }

  Future<List<ProtocolEntry>> allProtocols() async {
    final client = await _client();
    if (client == null) return [];
    try {
      return (await client
              .from('protocols')
              .select()
              .order('updated_at', ascending: false) as List)
          .map((r) => ProtocolEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<File?> downloadProtocol(ProtocolEntry entry) async {
    final client = await _client();
    if (client == null) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/team_protocols/${entry.localCacheName}');
      if (await file.exists()) return file;
      await file.parent.create(recursive: true);
      final bytes = await client.storage.from('protocols').download(entry.filePath);
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Deletes any locally-cached protocol PDF (under team_protocols/) that no
  /// longer corresponds to a protocol this device can currently see -- the
  /// device has no way to be reached remotely, so "delete from a user's
  /// phone" is implemented as this device pruning its own stale cache the
  /// next time it syncs (called from TeamProtocolsScreen's load and from
  /// the app-startup check), rather than a push from the Console.
  Future<void> pruneLocalProtocolCache() async {
    try {
      final visible = await myVisibleProtocols();
      final keepNames = visible.map((p) => p.localCacheName).toSet();
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/team_protocols');
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!keepNames.contains(name)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> acknowledgeProtocol(String protocolId) async {
    final client = await _client();
    if (client == null) return;
    try {
      await client.from('protocol_acknowledgments').upsert({
        'user_id': await _userId(),
        'callsign': await _callsign(),
        'protocol_id': protocolId,
        'acknowledged_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,protocol_id');
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAcknowledgments(String protocolId) async {
    final client = await _client();
    if (client == null) return [];
    try {
      return (await client
              .from('protocol_acknowledgments')
              .select()
              .eq('protocol_id', protocolId)
              .order('acknowledged_at', ascending: false) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> uploadProtocol({
    required String name,
    required String notes,
    required Uint8List bytes,
    required String uploadedBy,
    String? existingId,
    List<String>? targetUserIds,
    String? targetTeamId,
    String category = 'medical',
  }) async {
    final client = await _client();
    if (client == null) throw Exception('Supabase not configured');
    final id = existingId ?? _newUuid();
    final filePath = '$id.pdf';
    await client.storage.from('protocols').uploadBinary(
      filePath,
      bytes,
      fileOptions: const FileOptions(upsert: true, contentType: 'application/pdf'),
    );
    if (existingId != null) {
      final row = await client.from('protocols').select('version').eq('id', existingId).single();
      final newVer = ((row['version'] as int?) ?? 1) + 1;
      await client.from('protocols').update({
        'version': newVer,
        'file_path': filePath,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': uploadedBy,
        'notes': notes,
        'is_active': true,
        'target_user_ids': targetUserIds,
        'target_team_id': targetTeamId,
        'category': category,
      }).eq('id', existingId);
      // Invalidate acknowledgments so users must re-acknowledge this version
      await client.from('protocol_acknowledgments').delete().eq('protocol_id', existingId);
    } else {
      await client.from('protocols').insert({
        'id': id,
        'name': name,
        'version': 1,
        'file_path': filePath,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': uploadedBy,
        'notes': notes,
        'target_user_ids': targetUserIds,
        'target_team_id': targetTeamId,
        'category': category,
      });
    }
  }

  /// Changes who an already-pushed protocol is visible to, without
  /// re-uploading the file, bumping its version, or invalidating existing
  /// acknowledgments -- the document itself hasn't changed.
  Future<void> updateProtocolTargeting(
    String id, {
    List<String>? targetUserIds,
    String? targetTeamId,
  }) async {
    final client = await _client();
    if (client == null) return;
    await client.from('protocols').update({
      'target_user_ids': targetUserIds,
      'target_team_id': targetTeamId,
    }).eq('id', id);
  }

  Future<void> toggleActive(String id, bool active) async {
    final client = await _client();
    await client?.from('protocols').update({'is_active': active}).eq('id', id);
  }

  Future<void> deleteProtocol(ProtocolEntry entry) async {
    final client = await _client();
    if (client == null) return;
    try {
      await client.storage.from('protocols').remove([entry.filePath]);
    } catch (_) {}
    await client.from('protocols').delete().eq('id', entry.id);
  }

  /// Deletes every protocol in the library. Field devices prune their own
  /// stale local copies the next time they sync -- see pruneLocalProtocolCache.
  Future<void> deleteAllProtocols({String? category}) async {
    final all = await allProtocols();
    for (final p in all) {
      if (category != null && p.category != category) continue;
      await deleteProtocol(p);
    }
  }

  Future<List<Map<String, dynamic>>> adminGetReports() async {
    final client = await _client();
    if (client == null) return [];
    try {
      return (await client
              .from('patient_reports')
              .select()
              .order('submitted_at', ascending: false) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> adminGetCerts() async {
    final client = await _client();
    if (client == null) return [];
    try {
      final all = (await client
              .from('team_certs')
              .select()
              .order('uploaded_at', ascending: false) as List)
          .cast<Map<String, dynamic>>();
      // Pass 1: dedup by user_id|type|state (same-user duplicates).
      final seenUid = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final r in all) {
        final key = '${r['user_id']}|${r['license_type']}|${r['state']}';
        if (seenUid.add(key)) deduped.add(r);
      }
      // Pass 2: dedup by normalised-callsign|type|state across different user_ids
      // (same person uploaded under their name AND callsign, or after reinstall).
      final seenCs = <String>{};
      final final2 = <Map<String, dynamic>>[];
      for (final r in deduped) {
        final cs = (r['callsign'] as String? ?? '').toLowerCase().trim();
        final key = '$cs|${r['license_type']}|${r['state']}';
        if (cs.isEmpty || seenCs.add(key)) final2.add(r);
      }
      return final2;
    } catch (_) {
      return [];
    }
  }

  Future<bool> adminDeleteCert(String id, String filePath) async {
    final client = await _client();
    if (client == null) return false;
    try {
      if (filePath.isNotEmpty) {
        try { await client.storage.from('certs').remove([filePath]); } catch (_) {}
      }
      await client.from('team_certs').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}


class DeploymentOrder {
  final String id;
  final String title;
  final String notes;
  final String filePath;
  final String fileName;
  final DateTime uploadedAt;
  final String uploadedBy;
  // Null = broadcast to everyone (existing/default behavior, unchanged).
  // Non-null = only these user_ids should see this order.
  final List<String>? targetUserIds;

  const DeploymentOrder({
    required this.id,
    required this.title,
    required this.notes,
    required this.filePath,
    required this.fileName,
    required this.uploadedAt,
    required this.uploadedBy,
    this.targetUserIds,
  });

  factory DeploymentOrder.fromMap(Map<String, dynamic> m) => DeploymentOrder(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        filePath: m['file_path'] as String? ?? '',
        fileName: m['file_name'] as String? ?? '',
        uploadedAt: DateTime.tryParse(m['uploaded_at'] as String? ?? '') ?? DateTime.now(),
        uploadedBy: m['uploaded_by'] as String? ?? '',
        targetUserIds: (m['target_user_ids'] as List?)?.cast<String>(),
      );
}


extension DeploymentOrderService on ProtocolSyncService {
  Future<List<DeploymentOrder>> allDeploymentOrders() async {
    final client = await _client();
    if (client == null) return [];
    try {
      return (await client
              .from('deployment_orders')
              .select()
              .order('uploaded_at', ascending: false) as List)
          .map((r) => DeploymentOrder.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<DeploymentOrder>> pendingDeploymentOrders() async {
    final client = await _client();
    if (client == null) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      var userId = prefs.getString('tac_user_id') ?? '';
      final allOrders = (await client
              .from('deployment_orders')
              .select()
              .order('uploaded_at', ascending: false) as List)
          .map((r) => DeploymentOrder.fromMap(r as Map<String, dynamic>))
          .toList();
      // Untargeted orders (targetUserIds == null) are broadcast to everyone,
      // exactly as before this field existed. Targeted orders are only
      // visible to the user_ids listed.
      final orders = allOrders
          .where((o) => o.targetUserIds == null || o.targetUserIds!.contains(userId))
          .toList();
      if (userId.isEmpty) return orders;
      final viewedIds = (await client
              .from('deployment_order_views')
              .select('order_id')
              .eq('user_id', userId) as List)
          .map((r) => r['order_id'] as String)
          .toSet();
      return orders.where((o) => !viewedIds.contains(o.id)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markDeploymentOrderViewed(String orderId) async {
    final client = await _client();
    if (client == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('tac_user_id') ?? '';
      if (userId.isEmpty) return;
      await client.from('deployment_order_views').upsert(
        {'user_id': userId, 'order_id': orderId},
        onConflict: 'user_id,order_id',
      );
    } catch (_) {}
  }

  Future<({File? file, String? error})> downloadDeploymentOrderWithError(
      DeploymentOrder order) async {
    final client = await _client();
    if (client == null) return (file: null, error: 'Supabase not connected');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localFile =
          File('${dir.path}/deployment_orders/${order.id}_${order.fileName}');
      if (await localFile.exists()) return (file: localFile, error: null);
      await localFile.parent.create(recursive: true);

      // 1. Try SDK download (authenticated — works for any bucket type).
      try {
        final bytes = await client.storage
            .from('deployment_orders')
            .download(order.filePath);
        await localFile.writeAsBytes(bytes);
        return (file: localFile, error: null);
      } catch (_) {}

      // 2. Try signed URL (60-second validity, any bucket).
      try {
        final signed = await client.storage
            .from('deployment_orders')
            .createSignedUrl(order.filePath, 60);
        final resp = await http.get(Uri.parse(signed))
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          await localFile.writeAsBytes(resp.bodyBytes);
          return (file: localFile, error: null);
        }
      } catch (_) {}

      // 3. Fall back to public URL with anon key header.
      const base = 'https://vlgiclyuxaleyusalexo.supabase.co';
      const anon = 'sb_publishable_U6M_YMbubI1Y8qD4a3SKCA_Oeo6L75B';
      final resp = await http.get(
        Uri.parse('$base/storage/v1/object/deployment_orders/${order.filePath}'),
        headers: {'Authorization': 'Bearer $anon', 'apikey': anon},
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        await localFile.writeAsBytes(resp.bodyBytes);
        return (file: localFile, error: null);
      }
      return (file: null, error: 'HTTP ${resp.statusCode} — file may not be in storage. Ask admin to re-upload this order.');
    } catch (e) {
      return (file: null, error: e.toString());
    }
  }

  // Keep old signature for compatibility.
  Future<File?> downloadDeploymentOrder(DeploymentOrder order) async =>
      (await downloadDeploymentOrderWithError(order)).file;

  Future<void> uploadDeploymentOrder({
    required String title,
    required String notes,
    required Uint8List bytes,
    required String fileName,
    required String uploadedBy,
    List<String>? targetUserIds,
  }) async {
    final client = await _client();
    if (client == null) throw Exception('Supabase not configured');
    final id = _newUuid();
    final ext = fileName.contains('.') ? fileName.split('.').last : 'pdf';
    final storagePath = '$id.$ext';
    String savedPath = storagePath;

    // Try Supabase Storage first; fall back to base64 in file_path if unavailable.
    try {
      await client.storage.from('deployment_orders').uploadBinary(
        storagePath, bytes,
        fileOptions: FileOptions(
            upsert: true,
            contentType: ext == 'pdf' ? 'application/pdf' : 'application/octet-stream'),
      );
    } catch (_) {
      // Storage bucket not set up — embed as base64 so admin can still push orders.
      savedPath = 'base64:${base64.encode(bytes)}';
    }

    await client.from('deployment_orders').insert({
      'id': id,
      'title': title,
      'notes': notes,
      'file_path': savedPath,
      'file_name': fileName,
      'uploaded_at': DateTime.now().toIso8601String(),
      'uploaded_by': uploadedBy,
      'target_user_ids': targetUserIds,
    });
  }

  /// Fetches the raw file bytes for an order.
  Future<Uint8List?> fetchOrderBytes(DeploymentOrder order) async {
    // Base64 embedded directly in file_path (v1.0.0+40+).
    if (order.filePath.startsWith('base64:')) {
      try { return base64.decode(order.filePath.substring(7)); } catch (_) {}
    }
    // Storage-backed order (URL-fixed path like "{uuid}.pdf").
    if (order.filePath.isNotEmpty) {
      final client = await _client();
      if (client != null) {
        // 1. SDK authenticated download.
        try {
          return await client.storage
              .from('deployment_orders')
              .download(order.filePath);
        } catch (_) {}
        // 2. Public HTTP URL (bypasses SDK path validation entirely).
        try {
          const base = 'https://vlgiclyuxaleyusalexo.supabase.co';
          final url = '$base/storage/v1/object/public/deployment_orders/${order.filePath}';
          final resp = await http.get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            return resp.bodyBytes;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> deleteDeploymentOrder(DeploymentOrder order) async {
    final client = await _client();
    if (client == null) return;
    try {
      await client.storage.from('deployment_orders').remove([order.filePath]);
    } catch (_) {}
    await client.from('deployment_orders').delete().eq('id', order.id);
  }
}


Future<bool> showAdminPinDialog(BuildContext context) async {
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Admin Access'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: userCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(context, true),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enter')),
      ],
    ),
  );
  if (ok != true) return false;
  final correctUser = await ProtocolSyncService.instance.getAdminUsername();
  final correctPass = await ProtocolSyncService.instance.getAdminPassword();
  return userCtrl.text.trim() == correctUser && passCtrl.text == correctPass;
}


class ProtocolUpdateDialog extends StatefulWidget {
  final List<ProtocolEntry> protocols;
  const ProtocolUpdateDialog({required this.protocols, super.key});

  @override
  State<ProtocolUpdateDialog> createState() => _ProtocolUpdateDialogState();
}

class _ProtocolUpdateDialogState extends State<ProtocolUpdateDialog> {
  bool _acknowledging = false;

  Future<void> _ackAll() async {
    setState(() => _acknowledging = true);
    for (final p in widget.protocols) {
      await ProtocolSyncService.instance.acknowledgeProtocol(p.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.protocols.length;
    return AlertDialog(
      icon: const Icon(Icons.new_releases, color: Colors.orange, size: 32),
      title: Text('$n Protocol${n > 1 ? 's' : ''} Updated'),
      content: SizedBox(
        width: double.maxFinite,
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following protocol${n > 1 ? 's have' : ' has'} been updated. '
              'Tap each to see what changed, then acknowledge receipt.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: n,
                itemBuilder: (_, i) {
                  final p = widget.protocols[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ExpansionTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
                      title: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('v${p.version} — ${_fmt(p.updatedAt)}',
                          style: const TextStyle(fontSize: 11)),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      children: p.notes.isEmpty
                          ? []
                          : [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: Text(p.notes, style: const TextStyle(fontSize: 12)),
                              )
                            ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: _acknowledging ? null : _ackAll,
          icon: _acknowledging
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Acknowledge Receipt'),
        ),
      ],
    );
  }
}


class TeamProtocolsScreen extends StatefulWidget {
  const TeamProtocolsScreen({super.key});

  @override
  State<TeamProtocolsScreen> createState() => _TeamProtocolsScreenState();
}

class _TeamProtocolsScreenState extends State<TeamProtocolsScreen> {
  List<ProtocolEntry> _protocols = [];
  Set<String> _ackedIds = {};
  bool _loading = true;
  bool _notConfigured = false;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _notConfigured = false; });
    final ok = await SupabaseService.ensureInitialized();
    if (!ok) {
      setState(() { _loading = false; _notConfigured = true; });
      return;
    }
    final protocols = await ProtocolSyncService.instance.myVisibleProtocols(category: 'team');
    final pending = await ProtocolSyncService.instance.pendingProtocols(category: 'team');
    final pendingIds = pending.map((p) => p.id).toSet();
    setState(() {
      _protocols = protocols;
      _ackedIds = protocols.where((p) => !pendingIds.contains(p.id)).map((p) => p.id).toSet();
      _loading = false;
    });
    ProtocolSyncService.instance.pruneLocalProtocolCache();
  }

  Future<void> _viewProtocol(ProtocolEntry entry) async {
    setState(() => _downloading.add(entry.id));
    final file = await ProtocolSyncService.instance.downloadProtocol(entry);
    setState(() => _downloading.remove(entry.id));
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Download failed. Check your connection.')));
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProtocolViewScreen(file: file, entry: entry)),
    );
    if (!mounted) return;
    // Prompt explicit acknowledgment after the user has seen the document.
    final confirmed = await showReadAcknowledgment(
      context,
      title: entry.name,
      docType: 'Protocol',
    );
    if (confirmed) {
      await ProtocolSyncService.instance.acknowledgeProtocol(entry.id);
      if (mounted) setState(() => _ackedIds.add(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_notConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Protocols')),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Supabase not configured', style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text('Open Tac Map to connect to your Supabase project.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Protocols'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _protocols.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No team protocols published yet.', style: TextStyle(color: Colors.grey)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _protocols.length,
              itemBuilder: (_, i) => _buildCard(_protocols[i]),
            ),
    );
  }

  Widget _buildCard(ProtocolEntry entry) {
    final acked = _ackedIds.contains(entry.id);
    final downloading = _downloading.contains(entry.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.red, size: 36),
            if (!acked)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                  child: const Text('NEW',
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        title: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('v${entry.version}  •  Updated ${_fmt(entry.updatedAt)}',
              style: const TextStyle(fontSize: 11)),
          if (entry.notes.isNotEmpty)
            Text(entry.notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
        ]),
        isThreeLine: entry.notes.isNotEmpty,
        trailing: downloading
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                acked ? Icons.check_circle : Icons.download_outlined,
                color: acked ? Colors.green : Colors.blue,
              ),
        onTap: downloading ? null : () => _viewProtocol(entry),
      ),
    );
  }
}

class _ProtocolViewScreen extends StatelessWidget {
  final File file;
  final ProtocolEntry entry;
  const _ProtocolViewScreen({required this.file, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(entry.name, style: const TextStyle(fontSize: 15)),
          Text('v${entry.version}  •  ${_fmt(entry.updatedAt)}',
              style: const TextStyle(fontSize: 11)),
        ]),
      ),
      body: PdfViewer.file(file.path),
    );
  }
}


class AdminPanelScreen extends StatefulWidget {
  final VoidCallback? onLeaveAdmin;
  const AdminPanelScreen({super.key, this.onLeaveAdmin});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  @override
  void initState() {
    super.initState();
    ProtocolSyncService.instance.isAdminMode.then((ok) {
      if (!ok && mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.blue, child: Icon(Icons.description, color: Colors.white)),
            title: const Text('Protocol Management'),
            subtitle: const Text('Upload, update, and manage team protocols'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminProtocolScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.red, child: Icon(Icons.assignment, color: Colors.white)),
            title: const Text('Patient Reports'),
            subtitle: const Text('View all reports submitted by the team'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminReportsScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.orange, child: Icon(Icons.send_to_mobile, color: Colors.white)),
            title: const Text('Deployment Orders'),
            subtitle: const Text('Push orders and documents to all team members'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminDeploymentOrdersScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.workspace_premium, color: Colors.white)),
            title: const Text('Team Certifications'),
            subtitle: const Text('View certifications by state'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminCertsScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(Icons.vpn_key, color: Colors.white)),
            title: const Text('Access Codes'),
            subtitle: const Text('Manage app access codes for new users'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminAccessCodesScreen())),
          ),
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.indigo,
                child: Icon(Icons.how_to_reg, color: Colors.white)),
            title: const Text('Access Requests'),
            subtitle: const Text('Approve or deny self-serve access requests'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminAccessRequestsScreen())),
          ),
          // Apple Guideline 3.1.1: paid content on iOS must unlock only
          // through StoreKit — a manual bypass of the paywall isn't allowed
          // there, even from an admin-only screen. Kept on Android/Windows/
          // Mac for admin/test devices.
          if (!Platform.isIOS) ...[
            const Divider(indent: 72, endIndent: 16),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.lock_open, color: Colors.white)),
              title: const Text('Grant Full Access (This Device)'),
              subtitle: const Text('Bypass paywall for this device without purchasing'),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Grant Full Access?'),
                    content: const Text(
                        'This will unlock all features on this device without going through the paywall. Use this for admin and test devices.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Grant')),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('profile_purchase_unlocked', true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Full access granted. Restart the app to apply.'),
                    backgroundColor: Colors.green,
                  ));
                }
              },
            ),
          ],
          const Divider(indent: 72, endIndent: 16),
          ListTile(
            leading: const CircleAvatar(
                backgroundColor: Colors.grey, child: Icon(Icons.lock_outline, color: Colors.white)),
            title: const Text('Change Admin Credentials'),
            onTap: () => _changeCredentialsDialog(context),
          ),
          if (widget.onLeaveAdmin != null)
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.logout, color: Colors.white)),
              title: const Text('Leave Admin Mode',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text('Return to standard user view'),
              onTap: widget.onLeaveAdmin,
            ),
        ],
      ),
    );
  }

  Future<void> _changeCredentialsDialog(BuildContext context) async {
    final curUserCtrl = TextEditingController();
    final curPassCtrl = TextEditingController();
    final newUserCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Admin Credentials'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: curUserCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Current Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: curPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Current Password', border: OutlineInputBorder()),
            ),
            const Divider(height: 24),
            TextField(
              controller: newUserCtrl,
              decoration: const InputDecoration(
                  labelText: 'New Username', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New Password', border: OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final correctUser = await ProtocolSyncService.instance.getAdminUsername();
    final correctPass = await ProtocolSyncService.instance.getAdminPassword();
    if (curUserCtrl.text.trim() != correctUser || curPassCtrl.text != correctPass) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Current credentials incorrect')));
      }
      return;
    }
    final newUser = newUserCtrl.text.trim();
    final newPass = newPassCtrl.text;
    if (newUser.isEmpty || newPass.isEmpty) return;
    await ProtocolSyncService.instance.setAdminCredentials(newUser, newPass);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Credentials updated')));
    }
  }
}


class AdminProtocolScreen extends StatefulWidget {
  const AdminProtocolScreen({super.key});

  @override
  State<AdminProtocolScreen> createState() => _AdminProtocolScreenState();
}

enum _AdminProtocolScope { everyone, team, users }

/// A user_profiles row, just enough to pick recipients -- mirrors the
/// Command Console's protocols_console_screen.dart _RosterUser.
class _AdminRosterUser {
  final String userId;
  final String display;
  final String? teamId;
  const _AdminRosterUser({required this.userId, required this.display, this.teamId});
}

class _AdminProtocolScreenState extends State<AdminProtocolScreen> {
  List<ProtocolEntry> _protocols = [];
  Map<String, int> _ackCounts = {}; // protocolId → count
  List<Team> _teams = [];
  List<_AdminRosterUser> _roster = [];
  bool _loading = true;
  String _categoryFilter = 'medical';

  List<ProtocolEntry> get _filtered => _protocols.where((p) => p.category == _categoryFilter).toList();

  @override
  void initState() {
    super.initState();
    ProtocolSyncService.instance.isAdminMode.then((ok) {
      if (!ok && mounted) Navigator.pop(context);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final protocols = await ProtocolSyncService.instance.allProtocols();
    final teams = await AssetService.instance.fetchTeams();
    // Load ack counts for all protocols in parallel.
    final counts = <String, int>{};
    var roster = <_AdminRosterUser>[];
    if (SupabaseService.client != null) {
      try {
        final rows = await SupabaseService.client!
            .from('protocol_acknowledgments')
            .select('protocol_id') as List;
        for (final r in rows) {
          final pid = r['protocol_id'] as String? ?? '';
          counts[pid] = (counts[pid] ?? 0) + 1;
        }
      } catch (_) {}
      try {
        final rows = await SupabaseService.client!.from('user_profiles').select() as List;
        roster = rows
            .map((r) {
              final m = r as Map<String, dynamic>;
              final callsign = m['callsign'] as String? ?? '';
              final name = m['name'] as String? ?? '';
              return _AdminRosterUser(
                userId: m['user_id'] as String? ?? '',
                display: callsign.isNotEmpty ? callsign : (name.isNotEmpty ? name : (m['user_id'] as String? ?? '')),
                teamId: m['team_id'] as String?,
              );
            })
            .where((u) => u.userId.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    if (mounted) setState(() {
      _protocols = protocols;
      _ackCounts = counts;
      _teams = teams;
      _roster = roster;
      _loading = false;
    });
  }

  Future<void> _showUploadSheet({ProtocolEntry? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final notesCtrl = TextEditingController();
    Uint8List? bytes;
    String? fileName;
    var category = existing?.category ?? _categoryFilter;
    var scope = existing?.targetTeamId != null
        ? _AdminProtocolScope.team
        : existing?.targetUserIds != null
            ? _AdminProtocolScope.users
            : _AdminProtocolScope.everyone;
    Team? selectedTeam =
        existing?.targetTeamId == null ? null : _teams.where((t) => t.id == existing!.targetTeamId).firstOrNull;
    final selectedUsers = <String>{...?existing?.targetUserIds};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  existing == null ? 'Upload New Protocol' : 'Update — ${existing.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                if (existing == null) ...[
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Protocol Name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: existing == null ? 'Notes / Description' : 'What changed in this version?',
                    hintText: 'Added dosing table, updated contraindications…',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file),
                  label: Text(fileName ?? 'Choose PDF'),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      withData: true,
                    );
                    if (result == null) return;
                    final f = result.files.first;
                    Uint8List? b = f.bytes;
                    if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
                    setSt(() { bytes = b; fileName = f.name; });
                  },
                ),
                if (bytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(fileName ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                const SizedBox(height: 16),
                const Text('Destination', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'medical', label: Text('Protocols'), icon: Icon(Icons.menu_book_outlined)),
                    ButtonSegment(value: 'team', label: Text('Team Protocols'), icon: Icon(Icons.description_outlined)),
                  ],
                  selected: {category},
                  onSelectionChanged: (s) => setSt(() => category = s.first),
                ),
                const SizedBox(height: 16),
                const Text('Send to', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<_AdminProtocolScope>(
                  segments: const [
                    ButtonSegment(value: _AdminProtocolScope.everyone, label: Text('Everyone'), icon: Icon(Icons.public)),
                    ButtonSegment(value: _AdminProtocolScope.team, label: Text('Team'), icon: Icon(Icons.groups)),
                    ButtonSegment(value: _AdminProtocolScope.users, label: Text('Users'), icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) => setSt(() => scope = s.first),
                ),
                if (scope == _AdminProtocolScope.team) ...[
                  const SizedBox(height: 12),
                  if (_teams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No teams yet — create one from Roster > Assign to Team.', style: TextStyle(color: Colors.grey[600])),
                    )
                  else
                    DropdownButtonFormField<Team>(
                      initialValue: selectedTeam,
                      decoration: const InputDecoration(labelText: 'Team', border: OutlineInputBorder(), isDense: true),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                      onChanged: (v) => setSt(() => selectedTeam = v),
                    ),
                ],
                if (scope == _AdminProtocolScope.users) ...[
                  const SizedBox(height: 12),
                  const Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_roster.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No users found yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  SizedBox(
                    height: 180,
                    child: ListView(
                      children: _roster.map((u) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(u.display),
                            value: selectedUsers.contains(u.userId),
                            onChanged: (v) => setSt(() {
                              if (v == true) {
                                selectedUsers.add(u.userId);
                              } else {
                                selectedUsers.remove(u.userId);
                              }
                            }),
                          )).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _UploadButton(
                  existing: existing,
                  nameCtrl: nameCtrl,
                  notesCtrl: notesCtrl,
                  bytes: bytes,
                  category: category,
                  targetUserIds: scope == _AdminProtocolScope.users ? selectedUsers.toList() : null,
                  targetTeamId: scope == _AdminProtocolScope.team ? selectedTeam?.id : null,
                  onSuccess: () {
                    Navigator.pop(ctx);
                    _load();
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAcks(ProtocolEntry entry) async {
    final acks = await ProtocolSyncService.instance.getAcknowledgments(entry.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Acknowledgments — ${entry.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          acks.isEmpty
              ? const Expanded(
                  child: Center(child: Text('No acknowledgments yet', style: TextStyle(color: Colors.grey))))
              : Expanded(
                  child: ListView.builder(
                    itemCount: acks.length,
                    itemBuilder: (_, i) {
                      final a = acks[i];
                      final dt = DateTime.tryParse(a['acknowledged_at'] as String? ?? '');
                      return ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(a['callsign'] as String? ?? 'Unknown'),
                        subtitle: dt != null ? Text(_fmt(dt)) : null,
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ProtocolEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Protocol?'),
        content: Text('Permanently delete "${entry.name}"? '
            'This removes the file and all acknowledgment records.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProtocolSyncService.instance.deleteProtocol(entry);
      _load();
    }
  }

  Future<void> _confirmDeleteAll() async {
    final destLabel = _categoryFilter == 'medical' ? 'Protocols' : 'Team Protocols';
    final count = _filtered.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete All $destLabel?'),
        content: Text('Permanently delete all $count protocol(s) under "$destLabel"? '
            'This removes every file and all acknowledgment records, and clears them from any device that already downloaded them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProtocolSyncService.instance.deleteAllProtocols(category: _categoryFilter);
      _load();
    }
  }

  Future<void> _confirmEditRecipients(ProtocolEntry p) async {
    var scope = p.targetTeamId != null
        ? _AdminProtocolScope.team
        : p.targetUserIds != null
            ? _AdminProtocolScope.users
            : _AdminProtocolScope.everyone;
    Team? selectedTeam = p.targetTeamId == null ? null : _teams.where((t) => t.id == p.targetTeamId).firstOrNull;
    final selectedUsers = <String>{...?p.targetUserIds};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit Recipients — ${p.name}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<_AdminProtocolScope>(
                  segments: const [
                    ButtonSegment(value: _AdminProtocolScope.everyone, label: Text('Everyone'), icon: Icon(Icons.public)),
                    ButtonSegment(value: _AdminProtocolScope.team, label: Text('Team'), icon: Icon(Icons.groups)),
                    ButtonSegment(value: _AdminProtocolScope.users, label: Text('Users'), icon: Icon(Icons.person_pin_circle_outlined)),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) => setDialogState(() => scope = s.first),
                ),
                if (scope == _AdminProtocolScope.team) ...[
                  const SizedBox(height: 12),
                  if (_teams.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No teams yet — create one from Roster > Assign to Team.', style: TextStyle(color: Colors.grey[600])),
                    )
                  else
                    DropdownButtonFormField<Team>(
                      initialValue: selectedTeam,
                      decoration: const InputDecoration(labelText: 'Team', border: OutlineInputBorder(), isDense: true),
                      items: _teams.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                      onChanged: (v) => setDialogState(() => selectedTeam = v),
                    ),
                ],
                if (scope == _AdminProtocolScope.users) ...[
                  const SizedBox(height: 12),
                  const Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_roster.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No users found yet.', style: TextStyle(color: Colors.grey[600])),
                    ),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: _roster.map((u) => CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(u.display),
                            value: selectedUsers.contains(u.userId),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedUsers.add(u.userId);
                              } else {
                                selectedUsers.remove(u.userId);
                              }
                            }),
                          )).toList(),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (scope == _AdminProtocolScope.team && selectedTeam == null) ||
                      (scope == _AdminProtocolScope.users && selectedUsers.isEmpty)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ProtocolSyncService.instance.updateProtocolTargeting(
        p.id,
        targetUserIds: scope == _AdminProtocolScope.users ? selectedUsers.toList() : null,
        targetTeamId: scope == _AdminProtocolScope.team ? selectedTeam?.id : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated recipients for "${p.name}"')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocol Management'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          IconButton(icon: const Icon(Icons.code), tooltip: 'View SQL Schema', onPressed: _showSchema),
          if (_filtered.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Delete All',
              onPressed: _confirmDeleteAll,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(),
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Protocol'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'medical', label: Text('Protocols'), icon: Icon(Icons.menu_book_outlined)),
              ButtonSegment(value: 'team', label: Text('Team Protocols'), icon: Icon(Icons.description_outlined)),
            ],
            selected: {_categoryFilter},
            onSelectionChanged: (s) => setState(() => _categoryFilter = s.first),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.description_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('No protocols uploaded yet'),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _showUploadSheet(),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload First Protocol'),
                        ),
                      ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _buildCard(_filtered[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _buildCard(ProtocolEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(Icons.picture_as_pdf,
                color: entry.isActive ? Colors.red : Colors.grey, size: 32),
            title: Row(children: [
              Expanded(
                  child: Text(entry.name,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: entry.isActive ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(entry.isActive ? 'ACTIVE' : 'INACTIVE',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('v${entry.version}  •  ${_fmt(entry.updatedAt)}  •  by ${entry.updatedBy}',
                  style: const TextStyle(fontSize: 11)),
              Row(children: [
                const Icon(Icons.verified_user_outlined, size: 12, color: Colors.green),
                const SizedBox(width: 3),
                Text('${_ackCounts[entry.id] ?? 0} acknowledged',
                    style: const TextStyle(fontSize: 11, color: Colors.green)),
              ]),
              if (entry.notes.isNotEmpty)
                Text(entry.notes,
                    style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
            isThreeLine: entry.notes.isNotEmpty,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.update, size: 16),
                label: const Text('Update'),
                onPressed: () => _showUploadSheet(existing: entry),
              ),
              TextButton.icon(
                icon: const Icon(Icons.people_outline, size: 16),
                label: const Text('Acks'),
                onPressed: () => _showAcks(entry),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Recipients'),
                onPressed: () => _confirmEditRecipients(entry),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  entry.isActive ? Icons.toggle_on : Icons.toggle_off,
                  color: entry.isActive ? Colors.green : Colors.grey,
                  size: 28,
                ),
                tooltip: entry.isActive ? 'Deactivate' : 'Activate',
                onPressed: () async {
                  await ProtocolSyncService.instance.toggleActive(entry.id, !entry.isActive);
                  _load();
                },
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                onPressed: () => _confirmDelete(entry),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  void _showSchema() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supabase SQL — Run in SQL Editor'),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              _kAdditionalSql,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
        ],
      ),
    );
  }
}

// Stateful upload button to handle uploading state inside bottom sheet
class _UploadButton extends StatefulWidget {
  final ProtocolEntry? existing;
  final TextEditingController nameCtrl;
  final TextEditingController notesCtrl;
  final Uint8List? bytes;
  final String category;
  final List<String>? targetUserIds;
  final String? targetTeamId;
  final VoidCallback onSuccess;
  const _UploadButton({
    required this.existing,
    required this.nameCtrl,
    required this.notesCtrl,
    required this.bytes,
    required this.category,
    this.targetUserIds,
    this.targetTeamId,
    required this.onSuccess,
  });

  @override
  State<_UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<_UploadButton> {
  bool _uploading = false;

  Future<void> _upload() async {
    if (widget.bytes == null) return;
    final name = widget.existing?.name ?? widget.nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _uploading = true);
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString('tac_callsign') ?? 'Admin';
    try {
      await ProtocolSyncService.instance.uploadProtocol(
        name: name,
        notes: widget.notesCtrl.text.trim(),
        bytes: widget.bytes!,
        uploadedBy: callsign,
        existingId: widget.existing?.id,
        category: widget.category,
        targetUserIds: widget.targetUserIds,
        targetTeamId: widget.targetTeamId,
      );
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = widget.bytes != null &&
        !_uploading &&
        (widget.existing != null || widget.nameCtrl.text.trim().isNotEmpty);
    return FilledButton.icon(
      onPressed: canUpload ? _upload : null,
      icon: _uploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(widget.existing == null ? Icons.cloud_upload : Icons.update),
      label: Text(_uploading
          ? 'Uploading…'
          : widget.existing == null
              ? 'Upload Protocol'
              : 'Push Update'),
    );
  }
}


class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ProtocolSyncService.instance.isAdminMode.then((ok) {
      if (!ok && mounted) Navigator.pop(context);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ProtocolSyncService.instance.adminGetReports();
    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  void _viewReport(Map<String, dynamic> row) {
    try {
      final report = PatientReport.fromJson(row['report_data'] as Map<String, dynamic>);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.92,
          builder: (_, ctrl) => SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              report.formattedText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not parse report data')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patient Reports (${_rows.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Text('No reports submitted yet.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final row = _rows[i];
                    final data = (row['report_data'] as Map?)?.cast<String, dynamic>() ?? {};
                    final patientId = data['patientId'] as String? ?? '';
                    final formType = data['formType'] as String? ?? 'MIST';
                    final callsign = row['callsign'] as String? ?? 'Unknown';
                    final submitted =
                        DateTime.tryParse(row['submitted_at'] as String? ?? '');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.withValues(alpha: 0.12),
                          child: Text(formType == 'Pediatric' ? 'PED' : formType,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                        ),
                        title: Text(
                            patientId.isEmpty ? 'Unknown Patient' : patientId,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From: $callsign'),
                              if (submitted != null)
                                Text(_fmt(submitted),
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ]),
                        isThreeLine: true,
                        trailing: TextButton(
                            onPressed: () => _viewReport(row), child: const Text('View')),
                      ),
                    );
                  },
                ),
    );
  }
}


class AdminCertsScreen extends StatefulWidget {
  const AdminCertsScreen({super.key});

  @override
  State<AdminCertsScreen> createState() => _AdminCertsScreenState();
}

class _AdminCertsScreenState extends State<AdminCertsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ProtocolSyncService.instance.isAdminMode.then((ok) {
      if (!ok && mounted) Navigator.pop(context);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await ProtocolSyncService.instance.adminGetCerts();
    if (mounted) setState(() { _rows = rows; _loading = false; });
  }

  Map<String, List<Map<String, dynamic>>> _groupedByState() {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final row in _rows) {
      final state = (row['state'] as String?)?.trim();
      final key = (state == null || state.isEmpty) ? 'Unknown State' : state;
      groups.putIfAbsent(key, () => []).add(row);
    }
    final sorted = Map.fromEntries(
      groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return sorted;
  }

  Future<void> _viewCert(Map<String, dynamic> row) async {
    final client = SupabaseService.client;
    if (client == null) return;
    final filePath = row['file_path'] as String? ?? '';
    if (filePath.isEmpty) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 60,
          child: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading…'),
          ]),
        ),
      ),
    );

    try {
      final bytes = await client.storage.from('certs').download(filePath);
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog

      final isPdf = filePath.toLowerCase().endsWith('.pdf');
      if (isPdf) {
        final dir = await getTemporaryDirectory();
        final tempFile = File('${dir.path}/cert_${row['id']}.pdf');
        await tempFile.writeAsBytes(bytes);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                title: Text('${row['license_type']} — ${row['callsign']}',
                    style: const TextStyle(fontSize: 14)),
              ),
              body: PdfViewer.file(tempFile.path),
            ),
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text('${row['license_type']} — ${row['callsign']}',
                    style: const TextStyle(fontSize: 14)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              InteractiveViewer(child: Image.memory(bytes)),
            ]),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load cert: $e')));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> cert) async {
    final type = cert['license_type'] as String? ?? 'cert';
    final callsign = cert['callsign'] as String? ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Certification?'),
        content: Text('Delete $type for $callsign? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ProtocolSyncService.instance.adminDeleteCert(
      cert['id'] as String,
      cert['file_path'] as String? ?? '',
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _rows.removeWhere((r) => r['id'] == cert['id']));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Certification deleted.')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Delete failed — check Supabase connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final groups = _groupedByState();

    return Scaffold(
      appBar: AppBar(
        title: Text('Team Certifications (${_rows.length})'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _rows.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No certifications synced yet.', style: TextStyle(color: Colors.grey)),
                SizedBox(height: 8),
                Text('Certs are uploaded when team members add them in Cert Vault.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final state = groups.keys.elementAt(i);
                final certs = groups[state]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.withValues(alpha: 0.15),
                      child: const Icon(Icons.map_outlined, color: Colors.indigo),
                    ),
                    title: Text(state,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${certs.length} certification${certs.length != 1 ? 's' : ''}'),
                    initiallyExpanded: true,
                    children: certs.map((cert) {
                      final dt = DateTime.tryParse(cert['uploaded_at'] as String? ?? '');
                      final callsign = cert['callsign'] as String? ?? 'Unknown';
                      return ListTile(
                        leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                        title: Text(cert['license_type'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.person, size: 13, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(callsign,
                                    style: const TextStyle(fontSize: 12)),
                              ]),
                              if (dt != null)
                                Text('Uploaded ${_fmt(dt)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                            ]),
                        isThreeLine: true,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                            onPressed: () => _viewCert(cert),
                            child: const Text('View'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(cert),
                          ),
                        ]),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}


class AdminDeploymentOrdersScreen extends StatefulWidget {
  const AdminDeploymentOrdersScreen({super.key});

  @override
  State<AdminDeploymentOrdersScreen> createState() =>
      _AdminDeploymentOrdersScreenState();
}

class _AdminDeploymentOrdersScreenState
    extends State<AdminDeploymentOrdersScreen> {
  List<DeploymentOrder> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ProtocolSyncService.instance.isAdminMode.then((ok) {
      if (!ok && mounted) Navigator.pop(context);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final orders = await ProtocolSyncService.instance.allDeploymentOrders();
    if (mounted) setState(() { _orders = orders; _loading = false; });
  }

  Future<void> _showUploadSheet() async {
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    Uint8List? bytes;
    String? fileName;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('New Deployment Order',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                    labelText: 'Title', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes / Instructions',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: Text(fileName ?? 'Attach Document (PDF or image)'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'docx'],
                    withData: true,
                  );
                  if (result == null) return;
                  final f = result.files.first;
                  Uint8List? b = f.bytes;
                  if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
                  setSt(() { bytes = b; fileName = f.name; });
                },
              ),
              if (bytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(fileName ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.green)),
                ),
              const SizedBox(height: 16),
              _DeploymentUploadButton(
                titleCtrl: titleCtrl,
                notesCtrl: notesCtrl,
                bytes: bytes,
                fileName: fileName,
                onSuccess: () { Navigator.pop(ctx); _load(); },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DeploymentOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Order?'),
        content: Text('Permanently delete "${order.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ProtocolSyncService.instance.deleteDeploymentOrder(order);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deployment Orders'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showUploadSheet,
        icon: const Icon(Icons.upload_file),
        label: const Text('New Order'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.send_to_mobile, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No deployment orders yet'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _showUploadSheet,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Create First Order'),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _orders.length,
                  itemBuilder: (_, i) {
                    final o = _orders[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.assignment_outlined,
                            color: Colors.orange, size: 36),
                        title: Text(o.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${o.fileName}  •  ${_fmt(o.uploadedAt)}',
                                  style: const TextStyle(fontSize: 11)),
                              if (o.notes.isNotEmpty)
                                Text(o.notes,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey)),
                            ]),
                        isThreeLine: o.notes.isNotEmpty,
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                          onPressed: () => _confirmDelete(o),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _DeploymentUploadButton extends StatefulWidget {
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final Uint8List? bytes;
  final String? fileName;
  final VoidCallback onSuccess;
  const _DeploymentUploadButton({
    required this.titleCtrl,
    required this.notesCtrl,
    required this.bytes,
    required this.fileName,
    required this.onSuccess,
  });

  @override
  State<_DeploymentUploadButton> createState() =>
      _DeploymentUploadButtonState();
}

class _DeploymentUploadButtonState extends State<_DeploymentUploadButton> {
  bool _uploading = false;

  Future<void> _upload() async {
    if (widget.bytes == null || widget.fileName == null) return;
    final title = widget.titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _uploading = true);
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString('tac_callsign') ?? 'Admin';
    try {
      await ProtocolSyncService.instance.uploadDeploymentOrder(
        title: title,
        notes: widget.notesCtrl.text.trim(),
        bytes: widget.bytes!,
        fileName: widget.fileName!,
        uploadedBy: callsign,
      );
      widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = widget.bytes != null &&
        !_uploading &&
        widget.titleCtrl.text.trim().isNotEmpty;
    return FilledButton.icon(
      onPressed: canUpload ? _upload : null,
      icon: _uploading
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send),
      label: Text(_uploading ? 'Uploading…' : 'Push to Team'),
    );
  }
}


// ── Access Codes admin screen ─────────────────────────────────────────────────

class AdminAccessCodesScreen extends StatefulWidget {
  const AdminAccessCodesScreen({super.key});
  @override
  State<AdminAccessCodesScreen> createState() => _AdminAccessCodesScreenState();
}

class _AdminAccessCodesScreenState extends State<AdminAccessCodesScreen> {
  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    try {
      final rows = await SupabaseService.client!
          .from('app_access_codes')
          .select()
          .order('created_at', ascending: false);
      if (mounted) setState(() { _codes = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleBypass(Map<String, dynamic> row) async {
    final nowBypass = !(row['bypass_paywall'] as bool? ?? false);
    try {
      await SupabaseService.client!
          .from('app_access_codes')
          .update({'bypass_paywall': nowBypass})
          .eq('id', row['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _createCode() async {
    final codeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool bypass = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Create Access Code'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code *',
                hintText: 'e.g. AERI2025',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g. Alpha Team — Summer 2025',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: bypass,
              onChanged: (v) => setLocal(() => bypass = v),
              title: const Text('Bypass Paywall'),
              subtitle: const Text('User skips purchase requirement'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final code = codeCtrl.text.trim().toUpperCase();
    final desc = descCtrl.text.trim();
    codeCtrl.dispose();
    descCtrl.dispose();
    if (ok != true || code.isEmpty) return;
    try {
      await SupabaseService.client!.from('app_access_codes').insert({
        'code': code,
        'description': desc,
        'is_active': true,
        'bypass_paywall': bypass,
        'uses': 0,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> row) async {
    final nowActive = !(row['is_active'] as bool? ?? true);
    try {
      await SupabaseService.client!
          .from('app_access_codes')
          .update({'is_active': nowActive})
          .eq('id', row['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Code?'),
        content: Text('Delete "${row['code']}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.client!
          .from('app_access_codes')
          .delete()
          .eq('id', row['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Codes'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCode,
        icon: const Icon(Icons.add),
        label: const Text('New Code'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _codes.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.vpn_key_off_outlined, size: 56, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('No access codes yet.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _createCode,
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Code'),
                    ),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                  itemCount: _codes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final row = _codes[i];
                    final isActive = row['is_active'] as bool? ?? true;
                    final bypass = row['bypass_paywall'] as bool? ?? false;
                    final uses = row['uses'] as int? ?? 0;
                    final desc = row['description'] as String? ?? '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isActive ? Colors.teal : Colors.grey.shade300,
                        child: Icon(Icons.vpn_key,
                            color: isActive ? Colors.white : Colors.grey,
                            size: 20),
                      ),
                      title: Text(row['code'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: isActive ? null : Colors.grey,
                            decoration: isActive
                                ? null
                                : TextDecoration.lineThrough,
                          )),
                      subtitle: Text(
                        '${desc.isNotEmpty ? '$desc  •  ' : ''}$uses use${uses == 1 ? '' : 's'}  •  ${isActive ? 'Active' : 'Inactive'}${bypass ? '  •  Bypass' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Tooltip(
                          message: bypass ? 'Paywall bypass ON' : 'Paywall bypass OFF',
                          child: IconButton(
                            icon: Icon(
                              bypass ? Icons.shield_outlined : Icons.shield,
                              color: bypass ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                            onPressed: () => _toggleBypass(row),
                          ),
                        ),
                        Switch(
                          value: isActive,
                          onChanged: (_) => _toggleActive(row),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => _delete(row),
                          tooltip: 'Delete',
                        ),
                      ]),
                    );
                  },
                ),
    );
  }
}

/// Mobile counterpart to the Command Console's Access Requests screen —
/// review self-serve "request access" submissions and approve/deny them.
/// Reload-on-open/pull-to-refresh is sufficient here (no live subscription,
/// unlike the desktop screen — this is meant for occasional phone checks).
class AdminAccessRequestsScreen extends StatefulWidget {
  const AdminAccessRequestsScreen({super.key});
  @override
  State<AdminAccessRequestsScreen> createState() => _AdminAccessRequestsScreenState();
}

class _AdminAccessRequestsScreenState extends State<AdminAccessRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ok = await SupabaseService.ensureInitialized();
    if (!ok || !mounted) return;
    try {
      final rows = await SupabaseService.client!
          .from('access_requests')
          .select()
          .order('requested_at', ascending: false);
      if (mounted) setState(() { _requests = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> row, String status) async {
    try {
      await SupabaseService.client!.from('access_requests').update({
        'status': status,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
        'decided_by': 'Mobile Admin',
      }).eq('id', row['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access Requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No access requests yet', style: TextStyle(color: Colors.grey))),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _requests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final row = _requests[i];
                        final status = row['status'] as String? ?? 'pending';
                        final name = row['name'] as String? ?? '';
                        final callsign = row['callsign'] as String? ?? '';
                        final company = row['company'] as String? ?? '';
                        final email = row['email'] as String? ?? '';
                        final statusColor = switch (status) {
                          'approved' => Colors.green,
                          'denied' => Colors.red,
                          _ => Colors.orange,
                        };
                        return Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(status.toUpperCase(),
                                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ]),
                              if (callsign.isNotEmpty || company.isNotEmpty)
                                Text([if (callsign.isNotEmpty) callsign, if (company.isNotEmpty) company].join(' · '),
                                    style: TextStyle(color: Colors.grey[600])),
                              if (email.isNotEmpty)
                                Text(email, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              if (status == 'pending') ...[
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _decide(row, 'denied'),
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Deny'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _decide(row, 'approved'),
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                ]),
                              ],
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}


const _kAdditionalSql = '''
-- ResQruck — Supabase SQL schema
-- Safe to run multiple times (idempotent).

-- ── Core tables ───────────────────────────────────────────────────────────────

create table if not exists protocols (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  version int not null default 1,
  file_path text not null,
  is_active boolean default true,
  updated_at timestamptz default now(),
  updated_by text default '',
  notes text default ''
);

create table if not exists protocol_acknowledgments (
  id uuid default gen_random_uuid() primary key,
  user_id text not null,
  callsign text not null,
  protocol_id uuid references protocols(id) on delete cascade,
  acknowledged_at timestamptz default now(),
  unique(user_id, protocol_id)
);

create table if not exists patient_reports (
  id text primary key,
  user_id text not null,
  callsign text not null,
  report_data jsonb not null,
  submitted_at timestamptz default now()
);

alter table protocols enable row level security;
alter table protocol_acknowledgments enable row level security;
alter table patient_reports enable row level security;

do \$\$ begin
  create policy "public_access" on protocols
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

do \$\$ begin
  create policy "public_access" on protocol_acknowledgments
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

do \$\$ begin
  create policy "public_access" on patient_reports
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

insert into storage.buckets (id, name, public)
  values ('protocols', 'protocols', true)
  on conflict (id) do nothing;

do \$\$ begin
  create policy "public_protocols" on storage.objects
    for all using (bucket_id = 'protocols')
    with check (bucket_id = 'protocols');
exception when duplicate_object then null; end \$\$;

-- ── Team certifications ───────────────────────────────────────────────────────

create table if not exists team_certs (
  id text primary key,
  user_id text not null,
  callsign text not null,
  license_type text not null,
  state text not null,
  original_file_name text not null,
  uploaded_at timestamptz not null,
  file_path text not null,
  expiration_date date
);

alter table team_certs add column if not exists expiration_date date;

alter table team_certs enable row level security;

do \$\$ begin
  create policy "public_access" on team_certs
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

insert into storage.buckets (id, name, public)
  values ('certs', 'certs', false)
  on conflict (id) do nothing;

do \$\$ begin
  create policy "public_certs" on storage.objects
    for all using (bucket_id = 'certs')
    with check (bucket_id = 'certs');
exception when duplicate_object then null; end \$\$;

-- ── Deployment orders ─────────────────────────────────────────────────────────

create table if not exists deployment_orders (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  notes text default '',
  file_path text not null default '',
  file_name text not null default '',
  uploaded_at timestamptz default now(),
  uploaded_by text default ''
);

create table if not exists deployment_order_views (
  user_id text not null,
  order_id uuid references deployment_orders(id) on delete cascade,
  viewed_at timestamptz default now(),
  primary key (user_id, order_id)
);

alter table deployment_orders enable row level security;
alter table deployment_order_views enable row level security;

do \$\$ begin
  create policy "public_access" on deployment_orders
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

do \$\$ begin
  create policy "public_access" on deployment_order_views
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

insert into storage.buckets (id, name, public)
  values ('deployment_orders', 'deployment_orders', true)
  on conflict (id) do nothing;

do \$\$ begin
  create policy "public_orders" on storage.objects
    for all using (bucket_id = 'deployment_orders')
    with check (bucket_id = 'deployment_orders');
exception when duplicate_object then null; end \$\$;

-- ── Team availability ─────────────────────────────────────────────────────────

create table if not exists team_availability (
  user_id text not null,
  callsign text not null,
  date date not null,
  status text not null default 'Available',
  notes text default '',
  updated_at timestamptz default now(),
  primary key (user_id, date)
);

alter table team_availability enable row level security;

do \$\$ begin
  create policy "public_access" on team_availability
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

-- ── User profiles ─────────────────────────────────────────────────────────────

create table if not exists user_profiles (
  user_id text primary key,
  name text not null default '',
  callsign text not null default '',
  cert_level text not null default 'None',
  rt130 boolean not null default false,
  rope_rescue boolean not null default false,
  updated_at timestamptz default now()
);

alter table user_profiles enable row level security;

do \$\$ begin
  create policy "public_access" on user_profiles
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

-- ── Auto-migration function (called by the app on every startup) ──────────
-- SECURITY DEFINER means it runs as the DB owner even when called by the
-- anon key — so the app can apply schema changes without admin intervention
-- after this SQL has been run once.

create or replace function resqruck_auto_migrate()
returns void
language plpgsql
security definer
as \$func\$
begin
  -- tac_users: Life360 columns
  alter table if exists tac_users add column if not exists battery_level int;
  alter table if exists tac_users add column if not exists status text default 'Active';

  -- tac_breadcrumbs
  create table if not exists tac_breadcrumbs (
    id uuid default gen_random_uuid() primary key,
    user_id text not null,
    callsign text not null,
    mission_code text not null,
    lat double precision not null,
    lng double precision not null,
    recorded_at timestamptz default now()
  );
  begin
    alter table tac_breadcrumbs enable row level security;
    create policy "public_access" on tac_breadcrumbs
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- tac_zones
  create table if not exists tac_zones (
    id uuid default gen_random_uuid() primary key,
    mission_code text not null,
    name text not null,
    zone_type text not null default 'Custom',
    lat double precision not null,
    lng double precision not null,
    radius_m double precision not null default 100,
    created_by text not null default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_zones enable row level security;
    create policy "public_access" on tac_zones
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- tac_markers
  create table if not exists tac_markers (
    id uuid default gen_random_uuid() primary key,
    mission_code text not null,
    type text not null,
    label text not null default '',
    lat double precision not null,
    lng double precision not null,
    placed_by text not null default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_markers enable row level security;
    create policy "public_access" on tac_markers
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table tac_markers;
  exception when others then null;
  end;

  -- tac_sos
  create table if not exists tac_sos (
    id uuid default gen_random_uuid() primary key,
    user_id text not null,
    callsign text not null,
    mission_code text not null,
    lat double precision not null,
    lng double precision not null,
    message text default '',
    triggered_at timestamptz default now(),
    resolved_at timestamptz,
    resolved_by text default ''
  );
  begin
    alter table tac_sos enable row level security;
    create policy "public_access" on tac_sos
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- team_certs: expiration date column
  alter table if exists team_certs add column if not exists expiration_date date;

  -- team_positions: ATAK / CoT feed written by the Oracle Cloud CoT listener
  -- callsign is UNIQUE so the server can upsert by callsign on each position update
  create table if not exists team_positions (
    id uuid default gen_random_uuid() primary key,
    callsign text not null unique,
    lat double precision not null,
    lon double precision not null,
    role text not null default '',
    status text not null default 'Active',
    last_updated timestamptz default now()
  );
  begin
    alter table team_positions enable row level security;
    create policy "public_access" on team_positions
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    -- Enable realtime so the app receives live position updates
    alter publication supabase_realtime add table team_positions;
  exception when others then null;
  end;

  -- admin_alerts: real-time notifications delivered to admins
  create table if not exists admin_alerts (
    id uuid default gen_random_uuid() primary key,
    type text not null,
    title text not null,
    callsign text not null default '',
    body text not null default '',
    created_at timestamptz default now(),
    read boolean not null default false
  );
  begin
    alter table admin_alerts enable row level security;
    create policy "public_access" on admin_alerts
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table admin_alerts;
  exception when others then null;
  end;

  -- tac_pois: optional points of interest layer
  create table if not exists tac_pois (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    type text not null default 'generic',
    lat double precision not null,
    lng double precision not null,
    notes text default '',
    created_at timestamptz default now()
  );
  begin
    alter table tac_pois enable row level security;
    create policy "public_access" on tac_pois
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- deployment_orders: optional per-user targeting (NULL = broadcast to everyone, unchanged default)
  alter table if exists deployment_orders add column if not exists target_user_ids text[];

  -- incidents: formal admin-managed incident sessions, each wrapping a tac_map mission_code
  create table if not exists incidents (
    id uuid default gen_random_uuid() primary key,
    name text not null default '',
    mission_code text not null,
    status text not null default 'open',
    opened_at timestamptz default now(),
    closed_at timestamptz,
    opened_by text default '',
    notes text default ''
  );
  begin
    alter table incidents enable row level security;
    create policy "public_access" on incidents
      for all using (true) with check (true);
  exception when others then null;
  end;
  create unique index if not exists incidents_open_mission_code_uq
    on incidents (mission_code) where status = 'open';
  begin
    alter publication supabase_realtime add table incidents;
  exception when others then null;
  end;

  -- incident_members: durable roster attached to an incident by the admin console
  -- (kept separate from tac_users, which is deleted on mission leave and would
  -- otherwise silently lose incident history for anyone who goes offline)
  create table if not exists incident_members (
    id uuid default gen_random_uuid() primary key,
    incident_id uuid references incidents(id) on delete cascade,
    user_id text not null,
    callsign text not null default '',
    joined_at timestamptz default now(),
    left_at timestamptz,
    accepted_at timestamptz,
    unique(incident_id, user_id)
  );
  alter table if exists incident_members add column if not exists accepted_at timestamptz;
  begin
    alter table incident_members enable row level security;
    create policy "public_access" on incident_members
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table incident_members;
  exception when others then null;
  end;

  -- teams: standing organizational teams (not mission-specific), matching
  -- REMS roster conventions (Type 1/Type 2 resource typing, A/B squad
  -- designations). color_hex drives team color-coding on the map/roster.
  create table if not exists teams (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    color_hex text not null default '#2196F3',
    designation text not null default '',
    notes text default '',
    created_at timestamptz default now()
  );
  begin
    alter table teams enable row level security;
    create policy "public_access" on teams
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table teams;
  exception when others then null;
  end;

  -- user_profiles: single-resource typing (wildland fire ICS conventions —
  -- EMT, EMT-Paramedic, Rope Rescue Technician, Driver/Operator, Team Leader)
  -- and standing team membership. resource_type is intentionally free text,
  -- not a check constraint, matching how status/cert_level/zone_type are
  -- validated client-side elsewhere in this schema rather than locked at
  -- the DB level.
  alter table if exists user_profiles add column if not exists resource_type text default '';
  alter table if exists user_profiles add column if not exists team_id uuid references teams(id);

  -- deployment_status: where someone is relative to an incident assignment —
  -- Standby / In Transit / On Mission / Off Duty. Independent of incident
  -- membership: people can be on standby with assets pre-staged, or moving
  -- toward an incident, before any incident_members row exists for them.
  alter table if exists user_profiles add column if not exists deployment_status text default 'Standby';

  -- protocols: optional targeting, same shape as deployment_orders'
  -- target_user_ids above (NULL = broadcast to everyone, unchanged default).
  -- target_team_id additionally lets a medical director push to everyone on
  -- a given team without listing each member individually.
  alter table if exists protocols add column if not exists target_user_ids text[];
  alter table if exists protocols add column if not exists target_team_id uuid references teams(id);

  -- protocols: destination -- 'medical' feeds the home screen's "Protocols"
  -- card (medical-director-authorized content), 'team' feeds "Team
  -- Protocols" (team-specific, non-medical directions). Defaults to
  -- 'medical' since every row created before this column existed was
  -- medical content.
  alter table if exists protocols add column if not exists category text not null default 'medical';

  -- assets: persistent, org-wide resource registry (vehicles, equipment,
  -- caches). Not mission-scoped — where an asset currently is / who has it
  -- lives in asset_assignments below, so its history isn't lost when it moves.
  create table if not exists assets (
    id uuid default gen_random_uuid() primary key,
    type text not null,
    identifier text not null,
    status text not null default 'Available',
    notes text default '',
    created_at timestamptz default now(),
    unique(type, identifier)
  );
  begin
    alter table assets enable row level security;
    create policy "public_access" on assets
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table assets;
  exception when others then null;
  end;

  -- asset_assignments: polymorphic — an asset can be assigned to a user, a
  -- team, or a mission (incident). assignable_id is resolved by the app
  -- against user_profiles/teams/incidents based on assignable_type; Postgres
  -- can't natively FK-constrain across a type discriminator without a
  -- trigger, so referential integrity here is enforced app-side, same as
  -- incident_members.user_id elsewhere in this schema. The partial unique
  -- index ensures an asset has only one active assignment at a time.
  create table if not exists asset_assignments (
    id uuid default gen_random_uuid() primary key,
    asset_id uuid not null references assets(id) on delete cascade,
    assignable_type text not null check (assignable_type in ('user', 'team', 'mission')),
    assignable_id text not null,
    assigned_at timestamptz default now(),
    assigned_by text default '',
    unassigned_at timestamptz,
    notes text default ''
  );
  create unique index if not exists asset_assignments_one_active_uq
    on asset_assignments (asset_id) where unassigned_at is null;
  begin
    alter table asset_assignments enable row level security;
    create policy "public_access" on asset_assignments
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table asset_assignments;
  exception when others then null;
  end;

  -- app_settings: simple team-wide key/value config (currently just the
  -- shared team drive link patient reports can be sent to). Unlike admin
  -- credentials elsewhere (per-device, in SharedPreferences), this is meant
  -- to be the same for every device, so it lives here instead.
  create table if not exists app_settings (
    key text primary key,
    value text not null default ''
  );
  begin
    alter table app_settings enable row level security;
    create policy "public_access" on app_settings
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- device_push_tokens: one current FCM token per user_id, overwritten on
  -- each registration — mirrors the single-device assumption already baked
  -- into tac_user_id / callsign uniqueness elsewhere in this app.
  create table if not exists device_push_tokens (
    user_id text primary key,
    fcm_token text not null,
    platform text not null default '',
    updated_at timestamptz default now()
  );
  begin
    alter table device_push_tokens enable row level security;
    create policy "public_access" on device_push_tokens
      for all using (true) with check (true);
  exception when others then null;
  end;

  -- internal_secrets: NOT publicly readable — RLS is enabled with zero
  -- policies, which denies all access via the REST API (anon/authenticated
  -- roles), while the SECURITY DEFINER trigger function below (running as
  -- the table owner) bypasses RLS entirely, per Postgres's default
  -- owner-exempt-from-RLS behavior. This exists because Supabase's hosted
  -- Postgres doesn't grant superuser to any customer-accessible role
  -- (confirmed: `alter database ... set app.settings.x` fails with
  -- "permission denied" even from the SQL editor's own connection), so the
  -- originally-planned session-GUC approach for storing the push trigger
  -- secret isn't available — this table is the workaround.
  create table if not exists internal_secrets (
    key text primary key,
    value text not null
  );
  begin
    alter table internal_secrets enable row level security;
  exception when others then null;
  end;

  -- Fires on a new/reset incident assignment (mirrors the same
  -- accepted_at/left_at both-null guard used client-side in
  -- _subscribeMissionAssignments) and POSTs to the push-mission-assignment
  -- Edge Function so the assigned user gets a real push notification even
  -- if their app is closed. Silently no-ops (net.http_post still fires, but
  -- the function 401s) until the one-time push_trigger_secret row is
  -- inserted into internal_secrets.
  begin
    create extension if not exists pg_net;
  exception when others then null;
  end;

  create or replace function notify_incident_member_pending() returns trigger as \$trg\$
  declare
    secret_value text;
  begin
    select value into secret_value from internal_secrets where key = 'push_trigger_secret';
    perform net.http_post(
      url := 'https://vlgiclyuxaleyusalexo.supabase.co/functions/v1/push-mission-assignment',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-push-secret', coalesce(secret_value, '')
      ),
      body := jsonb_build_object('user_id', new.user_id, 'incident_id', new.incident_id)
    );
    return new;
  end;
  \$trg\$ language plpgsql security definer;

  drop trigger if exists incident_members_push_trigger on incident_members;
  create trigger incident_members_push_trigger
    after insert or update of accepted_at, left_at on incident_members
    for each row
    when (new.accepted_at is null and new.left_at is null)
    execute function notify_incident_member_pending();

  -- access_requests: self-serve "request access" gate ahead of the paywall.
  -- A user without an admin-issued access code can submit name/callsign/
  -- company/email here instead; nothing about the purchase flow is reachable
  -- until an admin sets status to 'approved' (see notify_access_decision
  -- below and the mobile app's pending-status check before the paywall).
  create table if not exists access_requests (
    id uuid default gen_random_uuid() primary key,
    user_id text not null unique,
    name text not null,
    callsign text not null default '',
    company text not null default '',
    email text not null default '',
    status text not null default 'pending',
    requested_at timestamptz default now(),
    decided_at timestamptz,
    decided_by text default ''
  );
  begin
    alter table access_requests enable row level security;
    create policy "public_access" on access_requests
      for all using (true) with check (true);
  exception when others then null;
  end;
  begin
    alter publication supabase_realtime add table access_requests;
  exception when others then null;
  end;

  -- Fires once per new access request, emailing the admin via the
  -- notify-access-request Edge Function (Resend). Same secret-table
  -- workaround as the push trigger above — see internal_secrets comment.
  create or replace function notify_new_access_request() returns trigger as \$areq\$
  declare
    secret_value text;
  begin
    select value into secret_value from internal_secrets where key = 'access_request_secret';
    perform net.http_post(
      url := 'https://vlgiclyuxaleyusalexo.supabase.co/functions/v1/notify-access-request',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-access-secret', coalesce(secret_value, '')
      ),
      body := jsonb_build_object('user_id', new.user_id)
    );
    return new;
  end;
  \$areq\$ language plpgsql security definer;

  drop trigger if exists access_requests_insert_trigger on access_requests;
  create trigger access_requests_insert_trigger
    after insert on access_requests
    for each row execute function notify_new_access_request();

  -- Fires when an admin approves/denies a request, pushing a notification
  -- to the requester's device via notify-access-decision (reuses the same
  -- FCM credential already set up for push-mission-assignment).
  create or replace function notify_access_decision() returns trigger as \$adec\$
  declare
    secret_value text;
  begin
    if new.status is distinct from old.status and new.status in ('approved', 'denied') then
      select value into secret_value from internal_secrets where key = 'access_request_secret';
      perform net.http_post(
        url := 'https://vlgiclyuxaleyusalexo.supabase.co/functions/v1/notify-access-decision',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-access-secret', coalesce(secret_value, '')
        ),
        body := jsonb_build_object('user_id', new.user_id, 'status', new.status)
      );
    end if;
    return new;
  end;
  \$adec\$ language plpgsql security definer;

  drop trigger if exists access_requests_decision_trigger on access_requests;
  create trigger access_requests_decision_trigger
    after update on access_requests
    for each row execute function notify_access_decision();
end;
\$func\$;

-- Allow the anon key (used by the app) to call this function.
grant execute on function resqruck_auto_migrate() to anon;
grant execute on function resqruck_auto_migrate() to authenticated;

-- ── Access codes (run once, outside the migration function) ──────────────────
create table if not exists app_access_codes (
  id uuid default gen_random_uuid() primary key,
  code text unique not null,
  description text not null default '',
  is_active boolean not null default true,
  bypass_paywall boolean not null default false,
  uses integer not null default 0,
  created_at timestamptz default now()
);
do \$\$ begin
  alter table app_access_codes add column if not exists bypass_paywall boolean not null default false;
exception when others then null;
end \$\$;
do \$\$ begin
  alter table app_access_codes enable row level security;
  create policy "public_access" on app_access_codes
    for all using (true) with check (true);
exception when others then null;
end \$\$;

-- ── Shift Tickets (transmitted, for the Command Console's archive) ────────────

create table if not exists shift_tickets (
  id uuid default gen_random_uuid() primary key,
  incident_name text default '',
  agreement_number text default '',
  resource_order_number text default '',
  equipment_make_model text default '',
  recipient_email text default '',
  subject text default '',
  file_path text not null default '',
  file_name text not null default '',
  sent_at timestamptz default now(),
  sent_by text default ''
);

alter table shift_tickets enable row level security;

do \$\$ begin
  create policy "public_access" on shift_tickets
    for all using (true) with check (true);
exception when duplicate_object then null; end \$\$;

insert into storage.buckets (id, name, public)
  values ('shift_tickets', 'shift_tickets', true)
  on conflict (id) do nothing;

do \$\$ begin
  create policy "public_shift_tickets" on storage.objects
    for all using (bucket_id = 'shift_tickets')
    with check (bucket_id = 'shift_tickets');
exception when duplicate_object then null; end \$\$;
''';


String _fmt(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

// ── Admin alert service ───────────────────────────────────────────────────────

class AdminAlertService {
  static Future<void> post({
    required String type,
    required String title,
    required String callsign,
    String body = '',
  }) async {
    final client = SupabaseService.client;
    if (client == null) return;
    try {
      await client.from('admin_alerts').insert({
        'type': type,
        'title': title,
        'callsign': callsign,
        'body': body,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}

// ── Read-acknowledgment prompt ────────────────────────────────────────────────

/// Shows a bottom sheet asking the user to confirm they have read [title].
/// Returns `true` if the user tapped "I Have Read This", `false` otherwise.
Future<bool> showReadAcknowledgment(
  BuildContext context, {
  required String title,
  required String docType, // e.g. 'Deployment Order' or 'Protocol'
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isDismissible: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => _ReadAckSheet(title: title, docType: docType),
      ) ??
      false;
}

class _ReadAckSheet extends StatelessWidget {
  final String title;
  final String docType;
  const _ReadAckSheet({required this.title, required this.docType});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = docType == 'Protocol'
        ? Icons.description_outlined
        : Icons.assignment_outlined;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          // Icon badge
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, color: cs.onPrimaryContainer, size: 28),
          ),
          const SizedBox(height: 14),
          Text('Acknowledge $docType',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.2))),
            child: const Text(
              'By tapping "I Have Read This", you confirm you have read '
              'and understood this document. Your acknowledgment is recorded '
              'with your name and the current date and time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('I Have Read This'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close Without Acknowledging'),
            ),
          ),
        ]),
      ),
    );
  }
}
