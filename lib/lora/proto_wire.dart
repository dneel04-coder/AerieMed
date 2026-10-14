import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire-format reader/writer.
///
/// Meshtastic's Client API speaks protobuf. The production plan is to commit
/// `protoc`-generated Dart classes under `lib/lora/gen/` (see that folder's
/// README). Until that build step is wired into CI, this hand-rolled codec
/// handles the handful of messages we actually touch — `ToRadio`, `FromRadio`,
/// `MeshPacket`, `Data`, `Position`, `User` — reading only the fields we need
/// and skipping everything else (protobuf is forward-compatible that way).
///
/// Wire types: 0 = varint, 1 = 64-bit, 2 = length-delimited, 5 = 32-bit.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder();

  Uint8List toBytes() => _b.toBytes();

  void _tag(int field, int wireType) => _varint((field << 3) | wireType);

  void _varint(int value) {
    var v = value < 0 ? value + (1 << 64) : value; // treat as unsigned
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        _b.addByte(byte);
        break;
      }
      _b.addByte(byte | 0x80);
    }
  }

  void varintField(int field, int value) {
    if (value == 0) return; // proto3 default — omit
    _tag(field, 0);
    _varint(value);
  }

  void boolField(int field, bool value) {
    if (!value) return;
    _tag(field, 0);
    _b.addByte(1);
  }

  /// fixed32 / sfixed32 (little-endian, wire type 5).
  void fixed32Field(int field, int value) {
    if (value == 0) return;
    _tag(field, 5);
    final bd = ByteData(4)..setInt32(0, value, Endian.little);
    _b.add(bd.buffer.asUint8List());
  }

  void bytesField(int field, List<int> value) {
    if (value.isEmpty) return;
    _tag(field, 2);
    _varint(value.length);
    _b.add(value);
  }

  void stringField(int field, String value) {
    if (value.isEmpty) return;
    bytesField(field, utf8.encode(value));
  }

  void messageField(int field, ProtoWriter sub) {
    final bytes = sub.toBytes();
    if (bytes.isEmpty) return;
    _tag(field, 2);
    _varint(bytes.length);
    _b.add(bytes);
  }
}

class ProtoField {
  final int field;
  final int wireType;
  final int? varint; // wire type 0
  final int? fixed32; // wire type 5 (signed int32)
  final Uint8List? bytes; // wire type 2

  ProtoField._(this.field, this.wireType, {this.varint, this.fixed32, this.bytes});

  bool get asBool => (varint ?? 0) != 0;
  int get asInt => varint ?? fixed32 ?? 0;
  String get asString => bytes == null ? '' : utf8.decode(bytes!, allowMalformed: true);
}

class ProtoReader {
  final Uint8List _data;
  int _pos = 0;

  ProtoReader(this._data);

  bool get done => _pos >= _data.length;

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _data[_pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Iterates fields in declaration order. Callers switch on `f.field`.
  Iterable<ProtoField> fields() sync* {
    while (!done) {
      final key = _readVarint();
      final field = key >> 3;
      final wireType = key & 0x7;
      switch (wireType) {
        case 0:
          yield ProtoField._(field, wireType, varint: _readVarint());
          break;
        case 1: // 64-bit
          final v = ByteData.sublistView(_data, _pos, _pos + 8).getInt64(0, Endian.little);
          _pos += 8;
          yield ProtoField._(field, wireType, varint: v);
          break;
        case 2:
          final len = _readVarint();
          final b = Uint8List.sublistView(_data, _pos, _pos + len);
          _pos += len;
          yield ProtoField._(field, wireType, bytes: b);
          break;
        case 5: // 32-bit
          final v = ByteData.sublistView(_data, _pos, _pos + 4).getInt32(0, Endian.little);
          _pos += 4;
          yield ProtoField._(field, wireType, fixed32: v);
          break;
        default:
          throw FormatException('Unsupported protobuf wire type $wireType');
      }
    }
  }
}
