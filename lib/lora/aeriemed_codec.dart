import 'dart:convert';
import 'dart:typed_data';

/// Compact binary codec for AerieMed traffic carried on Meshtastic private
/// portnum 260 (`PortNum.aeriemedApp`). Every encoded message must fit inside
/// one LoRa packet — the hard ceiling is ~230 bytes of `Data.payload`; we cap
/// our own frames at [kMaxPayload] and split free text into chunks.
///
/// Layout: byte 0 = (version << 5) | kind, then kind-specific fields.
/// Coordinates are int32 big-endian, degrees * 1e7. Strings are 1-byte length
/// prefixed UTF-8.

const int kCodecVersion = 1;
const int kMaxPayload = 200;

enum AmKind {
  pos(0),
  sos(1),
  markerUpsert(2),
  markerDelete(3),
  zoneUpsert(4),
  zoneDelete(5),
  triage(6),
  text(7),
  textChunk(8);

  const AmKind(this.wire);
  final int wire;

  static AmKind fromWire(int w) =>
      AmKind.values.firstWhere((k) => k.wire == w, orElse: () => throw const FormatException('unknown AmKind'));
}

sealed class AmMessage {
  const AmMessage();
  AmKind get kind;
}

class AmPos extends AmMessage {
  final String missionCode;
  final String nodeId; // keep short (<=32); a shortened tac user id
  final String callsign;
  final double lat;
  final double lng;
  final int battery; // 0–100, 255 = unknown
  final String status; // e.g. "Active"
  const AmPos({
    required this.missionCode,
    required this.nodeId,
    required this.callsign,
    required this.lat,
    required this.lng,
    this.battery = 255,
    this.status = '',
  });
  @override
  AmKind get kind => AmKind.pos;
}

class AmSos extends AmMessage {
  final String missionCode;
  final String nodeId;
  final String callsign;
  final double lat;
  final double lng;
  final bool resolved;
  const AmSos({
    required this.missionCode,
    required this.nodeId,
    required this.callsign,
    required this.lat,
    required this.lng,
    this.resolved = false,
  });
  @override
  AmKind get kind => AmKind.sos;
}

class AmMarkerUpsert extends AmMessage {
  final String missionCode;
  final String id; // stable client uuid
  final int type; // TacMarkerType.index
  final String label;
  final double lat;
  final double lng;
  final String placedBy;
  const AmMarkerUpsert({
    required this.missionCode,
    required this.id,
    required this.type,
    required this.label,
    required this.lat,
    required this.lng,
    this.placedBy = '',
  });
  @override
  AmKind get kind => AmKind.markerUpsert;
}

class AmMarkerDelete extends AmMessage {
  final String missionCode;
  final String id;
  const AmMarkerDelete({required this.missionCode, required this.id});
  @override
  AmKind get kind => AmKind.markerDelete;
}

class AmZoneUpsert extends AmMessage {
  final String missionCode;
  final String id;
  final int type;
  final String label;
  final List<({double lat, double lng})> points; // polygon vertices
  const AmZoneUpsert({
    required this.missionCode,
    required this.id,
    required this.type,
    required this.label,
    required this.points,
  });
  @override
  AmKind get kind => AmKind.zoneUpsert;
}

class AmZoneDelete extends AmMessage {
  final String missionCode;
  final String id;
  const AmZoneDelete({required this.missionCode, required this.id});
  @override
  AmKind get kind => AmKind.zoneDelete;
}

class AmTriage extends AmMessage {
  final String missionCode;
  final String nodeId;
  final int immediate; // T1 red
  final int delayed; // T2 yellow
  final int minor; // T3 green
  final int expectant; // T4 black
  const AmTriage({
    required this.missionCode,
    required this.nodeId,
    required this.immediate,
    required this.delayed,
    required this.minor,
    required this.expectant,
  });
  @override
  AmKind get kind => AmKind.triage;
}

class AmText extends AmMessage {
  final String missionCode;
  final String msgId; // 8 hex chars is plenty
  final String from;
  final String body;
  const AmText({
    required this.missionCode,
    required this.msgId,
    required this.from,
    required this.body,
  });
  @override
  AmKind get kind => AmKind.text;
}

class AmTextChunk extends AmMessage {
  final String missionCode;
  final String msgId;
  final String from;
  final int index;
  final int total;
  final String part;
  const AmTextChunk({
    required this.missionCode,
    required this.msgId,
    required this.from,
    required this.index,
    required this.total,
    required this.part,
  });
  @override
  AmKind get kind => AmKind.textChunk;
}

// ── encode ─────────────────────────────────────────────────────────────────

class _W {
  final BytesBuilder _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xff);
  void i32(int v) {
    final bd = ByteData(4)..setInt32(0, v, Endian.big);
    _b.add(bd.buffer.asUint8List());
  }

  void coord(double deg) => i32((deg * 1e7).round());
  void str(String s) {
    final bytes = utf8.encode(s);
    if (bytes.length > 255) throw FormatException('string too long for codec: ${bytes.length}');
    u8(bytes.length);
    _b.add(bytes);
  }

  Uint8List take() => _b.toBytes();
}

Uint8List encodeAerieMed(AmMessage m) {
  final w = _W()..u8((kCodecVersion << 5) | m.kind.wire);
  switch (m) {
    case AmPos p:
      w..str(p.missionCode)..str(p.nodeId)..str(p.callsign);
      w..coord(p.lat)..coord(p.lng)..u8(p.battery)..str(p.status);
    case AmSos s:
      w..str(s.missionCode)..str(s.nodeId)..str(s.callsign);
      w..coord(s.lat)..coord(s.lng)..u8(s.resolved ? 1 : 0);
    case AmMarkerUpsert mk:
      w..str(mk.missionCode)..str(mk.id)..u8(mk.type)..str(mk.label);
      w..coord(mk.lat)..coord(mk.lng)..str(mk.placedBy);
    case AmMarkerDelete d:
      w..str(d.missionCode)..str(d.id);
    case AmZoneUpsert z:
      w..str(z.missionCode)..str(z.id)..u8(z.type)..str(z.label)..u8(z.points.length);
      for (final pt in z.points) {
        w..coord(pt.lat)..coord(pt.lng);
      }
    case AmZoneDelete d:
      w..str(d.missionCode)..str(d.id);
    case AmTriage t:
      w..str(t.missionCode)..str(t.nodeId);
      w..u8(t.immediate)..u8(t.delayed)..u8(t.minor)..u8(t.expectant);
    case AmText t:
      w..str(t.missionCode)..str(t.msgId)..str(t.from)..str(t.body);
    case AmTextChunk c:
      w..str(c.missionCode)..str(c.msgId)..str(c.from)..u8(c.index)..u8(c.total)..str(c.part);
  }
  final out = w.take();
  if (out.length > kMaxPayload) {
    throw FormatException('AerieMed message ${m.kind} is ${out.length}B > $kMaxPayload cap');
  }
  return out;
}

/// Encode free text, splitting into [AmTextChunk]s when it doesn't fit one frame.
List<Uint8List> encodeText({
  required String missionCode,
  required String msgId,
  required String from,
  required String body,
}) {
  final single = AmText(missionCode: missionCode, msgId: msgId, from: from, body: body);
  try {
    return [encodeAerieMed(single)];
  } on FormatException {
    // fall through to chunking
  }
  // Overhead: version(1) + missionCode + msgId + from + index(1) + total(1) + part-len(1)
  final overhead = 1 + (1 + utf8.encode(missionCode).length) + (1 + utf8.encode(msgId).length) + (1 + utf8.encode(from).length) + 3;
  final budget = kMaxPayload - overhead;
  final bytes = utf8.encode(body);
  final chunks = <List<int>>[];
  for (var i = 0; i < bytes.length; i += budget) {
    chunks.add(bytes.sublist(i, (i + budget).clamp(0, bytes.length)));
  }
  return [
    for (var i = 0; i < chunks.length; i++)
      encodeAerieMed(AmTextChunk(
        missionCode: missionCode,
        msgId: msgId,
        from: from,
        index: i,
        total: chunks.length,
        part: utf8.decode(chunks[i]),
      )),
  ];
}

// ── decode ─────────────────────────────────────────────────────────────────

class _R {
  final Uint8List _d;
  int _p = 0;
  _R(this._d);
  int u8() => _d[_p++];
  int i32() {
    final v = ByteData.sublistView(_d, _p, _p + 4).getInt32(0, Endian.big);
    _p += 4;
    return v;
  }

  double coord() => i32() / 1e7;
  String str() {
    final len = u8();
    final s = utf8.decode(_d.sublist(_p, _p + len), allowMalformed: true);
    _p += len;
    return s;
  }
}

AmMessage decodeAerieMed(Uint8List bytes) {
  final r = _R(bytes);
  final head = r.u8();
  final version = head >> 5;
  if (version != kCodecVersion) {
    throw FormatException('unsupported AerieMed codec version $version');
  }
  final kind = AmKind.fromWire(head & 0x1f);
  switch (kind) {
    case AmKind.pos:
      return AmPos(
        missionCode: r.str(),
        nodeId: r.str(),
        callsign: r.str(),
        lat: r.coord(),
        lng: r.coord(),
        battery: r.u8(),
        status: r.str(),
      );
    case AmKind.sos:
      return AmSos(
        missionCode: r.str(),
        nodeId: r.str(),
        callsign: r.str(),
        lat: r.coord(),
        lng: r.coord(),
        resolved: r.u8() == 1,
      );
    case AmKind.markerUpsert:
      return AmMarkerUpsert(
        missionCode: r.str(),
        id: r.str(),
        type: r.u8(),
        label: r.str(),
        lat: r.coord(),
        lng: r.coord(),
        placedBy: r.str(),
      );
    case AmKind.markerDelete:
      return AmMarkerDelete(missionCode: r.str(), id: r.str());
    case AmKind.zoneUpsert:
      final mc = r.str();
      final id = r.str();
      final type = r.u8();
      final label = r.str();
      final n = r.u8();
      return AmZoneUpsert(
        missionCode: mc,
        id: id,
        type: type,
        label: label,
        points: [for (var i = 0; i < n; i++) (lat: r.coord(), lng: r.coord())],
      );
    case AmKind.zoneDelete:
      return AmZoneDelete(missionCode: r.str(), id: r.str());
    case AmKind.triage:
      return AmTriage(
        missionCode: r.str(),
        nodeId: r.str(),
        immediate: r.u8(),
        delayed: r.u8(),
        minor: r.u8(),
        expectant: r.u8(),
      );
    case AmKind.text:
      return AmText(missionCode: r.str(), msgId: r.str(), from: r.str(), body: r.str());
    case AmKind.textChunk:
      return AmTextChunk(
        missionCode: r.str(),
        msgId: r.str(),
        from: r.str(),
        index: r.u8(),
        total: r.u8(),
        part: r.str(),
      );
  }
}

/// Reassembles [AmTextChunk]s into complete messages. Feed every inbound chunk;
/// returns the joined body once all parts for a `msgId` have arrived.
class TextReassembler {
  final Map<String, Map<int, String>> _parts = {};
  final Map<String, int> _totals = {};

  ({String from, String body})? add(AmTextChunk c) {
    final byIdx = _parts.putIfAbsent(c.msgId, () => {});
    byIdx[c.index] = c.part;
    _totals[c.msgId] = c.total;
    if (byIdx.length < c.total) return null;
    final body = [for (var i = 0; i < c.total; i++) byIdx[i] ?? ''].join();
    _parts.remove(c.msgId);
    _totals.remove(c.msgId);
    return (from: c.from, body: body);
  }
}
