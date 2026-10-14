import 'dart:typed_data';

import 'proto_wire.dart';

/// Meshtastic Client API stream framing + the minimal message subset AerieMed
/// uses. Same wire format over USB-serial and BLE:
///
///   0x94 0xC3  <uint16 length, big-endian>  <length bytes of protobuf>
///
/// Reference: https://meshtastic.org/docs/development/device/client-api/
/// The protobuf field numbers below come from meshtastic/protobufs `mesh.proto`
/// and must be kept in sync with the pinned firmware — see `gen/README.md` for
/// the `protoc` path that replaces this hand-rolled subset.

const int kFrameStart1 = 0x94;
const int kFrameStart2 = 0xC3;
const int kMaxFrameLen = 512;

/// Meshtastic BLE GATT UUIDs (https://meshtastic.org/docs/development/device/client-api/).
/// Over BLE there is no 0x94/0xC3 stream framing — each characteristic
/// read/write is exactly one protobuf message.
const String kMeshtasticBleService = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const String kMeshtasticToRadioChar = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const String kMeshtasticFromRadioChar = '2c55e69e-4993-11ed-b878-0242ac120002';
const String kMeshtasticFromNumChar = 'ed9da18c-a800-4f66-a670-aa7547e34453';

/// Meshtastic PortNum values we care about.
class PortNum {
  static const int textMessageApp = 1;
  static const int positionApp = 3;
  static const int nodeInfoApp = 4;

  /// Private range 256–511. AerieMed's compact codec (see aeriemed_codec.dart).
  static const int aeriemedApp = 260;
}

/// Broadcast address (0xffffffff) used for `MeshPacket.to`.
const int kBroadcastAddr = -1; // fixed32, all bits set

/// Wraps a byte stream from the transport and yields complete protobuf frame
/// payloads (the bytes *inside* the 4-byte header). Tolerates partial reads and
/// resynchronises on garbage / debug text.
class FrameDecoder {
  final List<int> _buf = [];

  Iterable<Uint8List> add(List<int> chunk) sync* {
    _buf.addAll(chunk);
    while (true) {
      // find frame start
      while (_buf.length >= 2 && !(_buf[0] == kFrameStart1 && _buf[1] == kFrameStart2)) {
        _buf.removeAt(0);
      }
      if (_buf.length < 4) return;
      final len = (_buf[2] << 8) | _buf[3];
      if (len > kMaxFrameLen) {
        _buf.removeAt(0); // bad length — drop start byte and resync
        continue;
      }
      if (_buf.length < 4 + len) return;
      final payload = Uint8List.fromList(_buf.sublist(4, 4 + len));
      _buf.removeRange(0, 4 + len);
      yield payload;
    }
  }
}

/// Prefix a protobuf payload with the 4-byte Meshtastic frame header.
Uint8List encodeFrame(Uint8List protobufPayload) {
  final len = protobufPayload.length;
  final out = Uint8List(4 + len);
  out[0] = kFrameStart1;
  out[1] = kFrameStart2;
  out[2] = (len >> 8) & 0xff;
  out[3] = len & 0xff;
  out.setRange(4, 4 + len, protobufPayload);
  return out;
}

// ── ToRadio ────────────────────────────────────────────────────────────────
//
// These builders return the *unframed* ToRadio protobuf. The BLE transport
// writes it verbatim to the ToRadio characteristic; the serial transport wraps
// it with [encodeFrame] first. LoraService deals only in unframed messages.

/// `ToRadio { want_config_id = 3 }` — kicks off the config handshake.
Uint8List toRadioWantConfig(int nonce) =>
    (ProtoWriter()..varintField(3, nonce)).toBytes();

/// `ToRadio { disconnect = 4 }`.
Uint8List toRadioDisconnect() => (ProtoWriter()..boolField(4, true)).toBytes();

/// `ToRadio { packet = 1: MeshPacket }` carrying a `Data` payload.
Uint8List toRadioData({
  required int channel,
  required int portnum,
  required Uint8List payload,
  int to = kBroadcastAddr,
  bool wantAck = false,
}) {
  final data = ProtoWriter()
    ..varintField(1, portnum) // Data.portnum
    ..bytesField(2, payload); // Data.payload
  final packet = ProtoWriter()
    ..fixed32Field(2, to) // MeshPacket.to
    ..varintField(3, channel) // MeshPacket.channel
    ..messageField(4, data) // MeshPacket.decoded
    ..boolField(10, wantAck); // MeshPacket.want_ack
  final toRadio = ProtoWriter()..messageField(1, packet);
  return toRadio.toBytes();
}

// ── FromRadio ──────────────────────────────────────────────────────────────

class DecodedData {
  final int fromNode;
  final int toNode;
  final int channel;
  final int portnum;
  final Uint8List payload;
  final int rxTime; // epoch seconds, 0 if absent
  const DecodedData({
    required this.fromNode,
    required this.toNode,
    required this.channel,
    required this.portnum,
    required this.payload,
    this.rxTime = 0,
  });
}

class DecodedPosition {
  final int fromNode;
  final double? lat;
  final double? lon;
  final int? altitude;
  final int time;
  const DecodedPosition({
    required this.fromNode,
    this.lat,
    this.lon,
    this.altitude,
    this.time = 0,
  });
}

class DecodedNodeInfo {
  final int num;
  final String? userId;
  final String? longName;
  final String? shortName;
  const DecodedNodeInfo({required this.num, this.userId, this.longName, this.shortName});
}

/// Anything the caller may want out of a `FromRadio` frame.
class FromRadioEvent {
  final int? configCompleteId;
  final bool rebooted;
  final DecodedData? data;
  final DecodedPosition? position;
  final DecodedNodeInfo? nodeInfo;
  const FromRadioEvent({
    this.configCompleteId,
    this.rebooted = false,
    this.data,
    this.position,
    this.nodeInfo,
  });
}

/// Parse a `FromRadio` protobuf payload. Returns null for frames we don't model.
FromRadioEvent? parseFromRadio(Uint8List frame) {
  for (final f in ProtoReader(frame).fields()) {
    switch (f.field) {
      case 2: // MeshPacket packet
        return _parsePacket(f.bytes!);
      case 4: // NodeInfo node_info
        return FromRadioEvent(nodeInfo: _parseNodeInfo(f.bytes!));
      case 7: // uint32 config_complete_id
        return FromRadioEvent(configCompleteId: f.asInt);
      case 8: // bool rebooted
        return FromRadioEvent(rebooted: f.asBool);
    }
  }
  return null;
}

FromRadioEvent? _parsePacket(Uint8List bytes) {
  int from = 0, to = 0, channel = 0, rxTime = 0;
  Uint8List? decoded;
  for (final f in ProtoReader(bytes).fields()) {
    switch (f.field) {
      case 1:
        from = f.asInt;
        break;
      case 2:
        to = f.asInt;
        break;
      case 3:
        channel = f.asInt;
        break;
      case 4:
        decoded = f.bytes;
        break;
      case 7:
        rxTime = f.asInt;
        break;
    }
  }
  if (decoded == null) return null; // encrypted / no plaintext Data

  int portnum = 0;
  Uint8List payload = Uint8List(0);
  for (final f in ProtoReader(decoded).fields()) {
    switch (f.field) {
      case 1:
        portnum = f.asInt;
        break;
      case 2:
        payload = f.bytes ?? Uint8List(0);
        break;
    }
  }

  if (portnum == PortNum.positionApp) {
    return FromRadioEvent(position: _parsePosition(from, payload));
  }
  return FromRadioEvent(
    data: DecodedData(
      fromNode: from,
      toNode: to,
      channel: channel,
      portnum: portnum,
      payload: payload,
      rxTime: rxTime,
    ),
  );
}

DecodedPosition _parsePosition(int fromNode, Uint8List bytes) {
  int? latI, lonI, alt;
  var time = 0;
  for (final f in ProtoReader(bytes).fields()) {
    switch (f.field) {
      case 1:
        latI = f.asInt;
        break;
      case 2:
        lonI = f.asInt;
        break;
      case 3:
        alt = f.asInt;
        break;
      case 4:
        time = f.asInt;
        break;
    }
  }
  return DecodedPosition(
    fromNode: fromNode,
    lat: latI == null ? null : latI * 1e-7,
    lon: lonI == null ? null : lonI * 1e-7,
    altitude: alt,
    time: time,
  );
}

DecodedNodeInfo _parseNodeInfo(Uint8List bytes) {
  int num = 0;
  String? id, long, short;
  for (final f in ProtoReader(bytes).fields()) {
    switch (f.field) {
      case 1:
        num = f.asInt;
        break;
      case 2: // User user
        for (final u in ProtoReader(f.bytes!).fields()) {
          switch (u.field) {
            case 1:
              id = u.asString;
              break;
            case 2:
              long = u.asString;
              break;
            case 3:
              short = u.asString;
              break;
          }
        }
        break;
    }
  }
  return DecodedNodeInfo(num: num, userId: id, longName: long, shortName: short);
}
