import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'protocol_admin.dart' show SupabaseService;

/// A formal, admin-managed incident session. Wraps a tac_map `mission_code`
/// (the pre-existing ad-hoc join code field users already type into the
/// mobile app) with a name, lifecycle, and a durable member roster.
class TacIncident {
  final String id;
  final String name;
  final String missionCode;
  final String status; // 'open' | 'closed'
  final DateTime openedAt;
  final DateTime? closedAt;
  final String openedBy;
  final String notes;

  const TacIncident({
    required this.id,
    required this.name,
    required this.missionCode,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.openedBy = '',
    this.notes = '',
  });

  bool get isOpen => status == 'open';

  factory TacIncident.fromMap(Map<String, dynamic> m) => TacIncident(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        missionCode: m['mission_code'] as String? ?? '',
        status: m['status'] as String? ?? 'open',
        openedAt: DateTime.tryParse(m['opened_at'] as String? ?? '') ?? DateTime.now(),
        closedAt: m['closed_at'] != null ? DateTime.tryParse(m['closed_at'] as String) : null,
        openedBy: m['opened_by'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );
}

/// A field user attached to an incident's durable roster. Kept independent
/// of `tac_users` (which is deleted when a device leaves its mission) so
/// incident membership/history survives someone going offline.
class IncidentMember {
  final String id;
  final String incidentId;
  final String userId;
  final String callsign;
  final DateTime joinedAt;
  final DateTime? leftAt;
  final DateTime? acceptedAt;

  const IncidentMember({
    required this.id,
    required this.incidentId,
    required this.userId,
    required this.callsign,
    required this.joinedAt,
    this.leftAt,
    this.acceptedAt,
  });

  bool get isActive => leftAt == null;

  /// True when the console has assigned this member but they haven't yet
  /// accepted the assignment on their device (see IncidentService.acceptMembership).
  bool get isPending => leftAt == null && acceptedAt == null;

  factory IncidentMember.fromMap(Map<String, dynamic> m) => IncidentMember(
        id: m['id'] as String,
        incidentId: m['incident_id'] as String,
        userId: m['user_id'] as String,
        callsign: m['callsign'] as String? ?? '',
        joinedAt: DateTime.tryParse(m['joined_at'] as String? ?? '') ?? DateTime.now(),
        leftAt: m['left_at'] != null ? DateTime.tryParse(m['left_at'] as String) : null,
        acceptedAt: m['accepted_at'] != null ? DateTime.tryParse(m['accepted_at'] as String) : null,
      );
}

/// A pending incident assignment, as seen by the assigned field device —
/// pairs the membership row with the incident it points to so the app can
/// show a name and know which mission_code to join on Accept.
class PendingAssignment {
  final IncidentMember member;
  final TacIncident incident;
  const PendingAssignment({required this.member, required this.incident});
}

class IncidentService {
  IncidentService._();
  static final instance = IncidentService._();

  Future<SupabaseClient?> _client() async {
    await SupabaseService.ensureInitialized();
    return SupabaseService.client;
  }

  /// Short, easy-to-read-aloud code for field users to type into the
  /// existing mobile "Join Mission" screen — same free-text field they
  /// already use today, this just generates one instead of the admin
  /// having to make one up.
  String generateMissionCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1 ambiguity
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<List<TacIncident>> fetchIncidents({bool? openOnly}) async {
    final client = await _client();
    if (client == null) return [];
    try {
      var query = client.from('incidents').select();
      if (openOnly == true) query = query.eq('status', 'open');
      final rows = await query.order('opened_at', ascending: false) as List;
      return rows.map((r) => TacIncident.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<TacIncident?> createIncident({
    required String name,
    required String missionCode,
    String openedBy = '',
  }) async {
    final client = await _client();
    if (client == null) return null;
    final row = await client.from('incidents').insert({
      'name': name,
      'mission_code': missionCode,
      'opened_by': openedBy,
    }).select().single();
    return TacIncident.fromMap(row);
  }

  Future<void> closeIncident(String id) async {
    final client = await _client();
    if (client == null) return;
    await client.from('incidents').update({
      'status': 'closed',
      'closed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> reopenIncident(String id) async {
    final client = await _client();
    if (client == null) return;
    await client.from('incidents').update({
      'status': 'open',
      'closed_at': null,
    }).eq('id', id);
  }

  Future<List<IncidentMember>> fetchMembers(String incidentId) async {
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client
          .from('incident_members')
          .select()
          .eq('incident_id', incidentId)
          .order('joined_at') as List;
      return rows.map((r) => IncidentMember.fromMap(r as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds (or re-activates, clearing `left_at`) a member on the incident
  /// roster. Always resets `accepted_at` to null — upsert only touches the
  /// columns given here, so a re-assignment (e.g. after they'd previously
  /// accepted and later left) would otherwise leave the old accepted_at
  /// timestamp in place and the mobile accept-prompt would never fire again.
  Future<void> addMember(String incidentId, {required String userId, required String callsign}) async {
    final client = await _client();
    if (client == null) return;
    await client.from('incident_members').upsert({
      'incident_id': incidentId,
      'user_id': userId,
      'callsign': callsign,
      'left_at': null,
      'accepted_at': null,
    }, onConflict: 'incident_id,user_id');
  }

  Future<void> markMemberLeft(String memberId) async {
    final client = await _client();
    if (client == null) return;
    await client.from('incident_members').update({
      'left_at': DateTime.now().toIso8601String(),
    }).eq('id', memberId);
  }

  Future<void> acceptMembership(String memberId) async {
    final client = await _client();
    if (client == null) return;
    await client.from('incident_members').update({
      'accepted_at': DateTime.now().toIso8601String(),
    }).eq('id', memberId);
  }

  /// Assignments made to this user that they haven't accepted yet, newest
  /// first — surfaced on the mobile side as an "accept mission assignment" prompt.
  Future<List<PendingAssignment>> fetchPendingForUser(String userId) async {
    if (userId.isEmpty) return [];
    final client = await _client();
    if (client == null) return [];
    try {
      final rows = await client
          .from('incident_members')
          .select('*, incidents(*)')
          .eq('user_id', userId)
          .isFilter('accepted_at', null)
          .isFilter('left_at', null)
          .order('joined_at', ascending: false) as List;
      return rows
          .map((r) {
            final m = r as Map<String, dynamic>;
            final incidentMap = m['incidents'] as Map<String, dynamic>?;
            if (incidentMap == null) return null;
            return PendingAssignment(
              member: IncidentMember.fromMap(m),
              incident: TacIncident.fromMap(incidentMap),
            );
          })
          .whereType<PendingAssignment>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
