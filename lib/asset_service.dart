import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;

/// A physical resource (vehicle, equipment, cache) in the org-wide asset
/// registry. Not mission-scoped — where an asset currently is / who has it
/// lives in AssetAssignment, so its history isn't lost when it moves.
class Asset {
  final String id;
  final String type;
  final String identifier;
  final String status;
  final String notes;
  final DateTime createdAt;

  const Asset({
    required this.id,
    required this.type,
    required this.identifier,
    required this.status,
    this.notes = '',
    required this.createdAt,
  });

  factory Asset.fromMap(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        type: m['type'] as String? ?? '',
        identifier: m['identifier'] as String? ?? '',
        status: m['status'] as String? ?? 'Available',
        notes: m['notes'] as String? ?? '',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// What kind of entity an asset is assigned to. Matches the
/// `assignable_type` check constraint on asset_assignments.
enum AssignableType {
  user,
  team,
  mission;

  String get value => name;

  static AssignableType parse(String v) =>
      AssignableType.values.firstWhere((t) => t.value == v, orElse: () => AssignableType.user);
}

/// A (possibly historical) assignment of an asset to a user, team, or
/// mission. assignable_id is resolved by the caller against
/// user_profiles/teams/incidents based on assignableType — Postgres can't
/// natively FK-constrain across a type discriminator, so this isn't
/// enforced at the DB level (same as incident_members.user_id elsewhere).
class AssetAssignment {
  final String id;
  final String assetId;
  final AssignableType assignableType;
  final String assignableId;
  final DateTime assignedAt;
  final String assignedBy;
  final DateTime? unassignedAt;
  final String notes;

  const AssetAssignment({
    required this.id,
    required this.assetId,
    required this.assignableType,
    required this.assignableId,
    required this.assignedAt,
    this.assignedBy = '',
    this.unassignedAt,
    this.notes = '',
  });

  bool get isActive => unassignedAt == null;

  factory AssetAssignment.fromMap(Map<String, dynamic> m) => AssetAssignment(
        id: m['id'] as String,
        assetId: m['asset_id'] as String,
        assignableType: AssignableType.parse(m['assignable_type'] as String? ?? 'user'),
        assignableId: m['assignable_id'] as String,
        assignedAt: DateTime.tryParse(m['assigned_at'] as String? ?? '') ?? DateTime.now(),
        assignedBy: m['assigned_by'] as String? ?? '',
        unassignedAt: m['unassigned_at'] != null ? DateTime.tryParse(m['unassigned_at'] as String) : null,
        notes: m['notes'] as String? ?? '',
      );
}

/// A standing organizational team (not mission-specific) — REMS roster
/// conventions (Type 1/Type 2 resource typing, A/B squad designations).
class Team {
  final String id;
  final String name;
  final String colorHex;
  final String designation;
  final String notes;

  const Team({
    required this.id,
    required this.name,
    this.colorHex = '#2196F3',
    this.designation = '',
    this.notes = '',
  });

  factory Team.fromMap(Map<String, dynamic> m) => Team(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        colorHex: m['color_hex'] as String? ?? '#2196F3',
        designation: m['designation'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );
}

class AssetService {
  AssetService._();
  static final instance = AssetService._();

  Future<SupabaseClient?> _client() async {
    await SupabaseService.ensureInitialized();
    return SupabaseService.client;
  }

  // ── Asset CRUD ────────────────────────────────────────────────────────────

  Future<List<Asset>> fetchAssets({String? type, String? status}) async {
    final client = await _client();
    if (client == null) return [];
    try {
      var query = client.from('assets').select();
      if (type != null) query = query.eq('type', type);
      if (status != null) query = query.eq('status', status);
      final rows = await query.order('identifier') as List;
      return rows.map((r) => Asset.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Asset?> createAsset({
    required String type,
    required String identifier,
    String status = 'Available',
    String notes = '',
  }) async {
    final client = await _client();
    if (client == null) return null;
    final row = await client.from('assets').insert({
      'type': type,
      'identifier': identifier,
      'status': status,
      'notes': notes,
    }).select().single();
    return Asset.fromMap(row);
  }

  Future<void> updateAsset(
    String id, {
    String? type,
    String? identifier,
    String? status,
    String? notes,
  }) async {
    final client = await _client();
    if (client == null) return;
    final updates = <String, dynamic>{
      if (type != null) 'type': type,
      if (identifier != null) 'identifier': identifier,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
    };
    if (updates.isEmpty) return;
    await client.from('assets').update(updates).eq('id', id);
  }

  Future<void> deleteAsset(String id) async {
    final client = await _client();
    if (client == null) return;
    // Assignment history goes with it (asset_id references assets(id) on delete cascade).
    await client.from('assets').delete().eq('id', id);
  }

  // ── Assignments ───────────────────────────────────────────────────────────

  Future<AssetAssignment?> _assignTo(
    String assetId,
    AssignableType type,
    String entityId, {
    String assignedBy = '',
    String notes = '',
  }) async {
    final client = await _client();
    if (client == null) return null;
    // "Assign" always means "make this the current assignment" — close out
    // any existing active assignment first rather than throwing on the
    // one-active-assignment-per-asset unique index. This is a transfer, not
    // an error case, when the asset is already assigned somewhere else.
    await unassignAsset(assetId, unassignedBy: assignedBy);
    final row = await client.from('asset_assignments').insert({
      'asset_id': assetId,
      'assignable_type': type.value,
      'assignable_id': entityId,
      'assigned_by': assignedBy,
      'notes': notes,
    }).select().single();
    return AssetAssignment.fromMap(row);
  }

  Future<AssetAssignment?> assignAssetToUser(
    String assetId,
    String userId, {
    String assignedBy = '',
    String notes = '',
  }) =>
      _assignTo(assetId, AssignableType.user, userId, assignedBy: assignedBy, notes: notes);

  Future<AssetAssignment?> assignAssetToTeam(
    String assetId,
    String teamId, {
    String assignedBy = '',
    String notes = '',
  }) =>
      _assignTo(assetId, AssignableType.team, teamId, assignedBy: assignedBy, notes: notes);

  Future<AssetAssignment?> assignAssetToMission(
    String assetId,
    String missionId, {
    String assignedBy = '',
    String notes = '',
  }) =>
      _assignTo(assetId, AssignableType.mission, missionId, assignedBy: assignedBy, notes: notes);

  /// Closes out this asset's current active assignment, if any. A no-op if
  /// the asset isn't currently assigned to anything.
  Future<void> unassignAsset(String assetId, {String unassignedBy = ''}) async {
    final client = await _client();
    if (client == null) return;
    await client
        .from('asset_assignments')
        .update({'unassigned_at': DateTime.now().toUtc().toIso8601String()})
        .eq('asset_id', assetId)
        .isFilter('unassigned_at', null);
  }

  /// All assignments (active and historical) for a given user/team/mission —
  /// e.g. getAssignmentsFor('team', someTeamId) to see everything ever
  /// assigned to that team. Filter by .isActive for just the current ones.
  Future<List<AssetAssignment>> getAssignmentsFor(AssignableType entityType, String entityId) async {
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client
          .from('asset_assignments')
          .select()
          .eq('assignable_type', entityType.value)
          .eq('assignable_id', entityId)
          .order('assigned_at', ascending: false) as List;
      return rows.map((r) => AssetAssignment.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Assets with no currently-active assignment, optionally narrowed to one
  /// type — the pool an "Assign Asset" picker should offer.
  Future<List<Asset>> fetchUnassignedAssets({String? type}) async {
    final client = await _client();
    if (client == null) return [];
    try {
      var query = client.from('assets').select();
      if (type != null) query = query.eq('type', type);
      final assetRows = await query.order('identifier') as List;
      final assets = assetRows.map((r) => Asset.fromMap(r as Map<String, dynamic>)).toList();
      final activeRows =
          await client.from('asset_assignments').select('asset_id').isFilter('unassigned_at', null) as List;
      final assignedIds = activeRows.map((r) => r['asset_id'] as String).toSet();
      return assets.where((a) => !assignedIds.contains(a.id)).toList();
    } catch (_) {
      return [];
    }
  }

  /// All assignments (active and historical) for one asset.
  Future<List<AssetAssignment>> getAssignmentsForAsset(String assetId) async {
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client
          .from('asset_assignments')
          .select()
          .eq('asset_id', assetId)
          .order('assigned_at', ascending: false) as List;
      return rows.map((r) => AssetAssignment.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Every currently-active assignment, across all assets, in one query —
  /// for screens (like the assets management list) that need to show
  /// "assigned to" for many assets at once without a query per asset.
  Future<List<AssetAssignment>> fetchActiveAssignments() async {
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client.from('asset_assignments').select().isFilter('unassigned_at', null) as List;
      return rows.map((r) => AssetAssignment.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Team>> fetchTeams() async {
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client.from('teams').select().order('name') as List;
      return rows.map((r) => Team.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
