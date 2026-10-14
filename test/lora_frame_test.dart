import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resqruck/lora/aeriemed_codec.dart';
import 'package:resqruck/lora/meshtastic_frame.dart';
import 'package:resqruck/lora/lora_transport.dart';

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('Meshtastic stream framing', () {
    test('encodeFrame prefixes the 4-byte header', () {
      final f = encodeFrame(Uint8List.fromList([1, 2, 3]));
      expect(f.sublist(0, 4), [0x94, 0xC3, 0x00, 0x03]);
      expect(f.sublist(4), [1, 2, 3]);
    });

    test('decoder reassembles a frame split across chunks', () {
      final frame = encodeFrame(Uint8List.fromList(List.filled(10, 0xAB)));
      final dec = FrameDecoder();
      final out = <Uint8List>[];
      out.addAll(dec.add(frame.sublist(0, 3)));
      out.addAll(dec.add(frame.sublist(3, 8)));
      out.addAll(dec.add(frame.sublist(8)));
      expect(out.length, 1);
      expect(out.single, List.filled(10, 0xAB));
    });

    test('decoder resynchronises past leading garbage / debug text', () {
      final frame = encodeFrame(Uint8List.fromList([9, 9, 9]));
      final noise = Uint8List.fromList('INFO boot ok\n'.codeUnits + frame);
      final dec = FrameDecoder();
      final out = dec.add(noise).toList();
      expect(out.single, [9, 9, 9]);
    });

    test('two back-to-back frames in one chunk', () {
      final a = encodeFrame(Uint8List.fromList([1]));
      final b = encodeFrame(Uint8List.fromList([2, 2]));
      final dec = FrameDecoder();
      final out = dec.add(Uint8List.fromList([...a, ...b])).toList();
      expect(out.map((e) => e.toList()), [
        [1],
        [2, 2],
      ]);
    });
  });

  group('ToRadio builders (unframed protobuf)', () {
    test('want_config sets field 3 as a varint', () {
      final f = toRadioWantConfig(0x0102);
      // ToRadio field 3 (want_config_id), varint tag = (3<<3)|0 = 0x18
      expect(f[0], 0x18);
    });

    test('serial transport framing wraps a ToRadio message', () {
      final f = toRadioWantConfig(0x0102);
      final framed = encodeFrame(f);
      expect(framed.sublist(0, 2), [0x94, 0xC3]);
      final back = FrameDecoder().add(framed).single;
      expect(back, f);
    });

    test('data message carries the AerieMed portnum payload', () {
      final payload = encodeAerieMed(
        const AmMarkerDelete(missionCode: 'A1', id: 'm1'),
      );
      final f = toRadioData(channel: 0, portnum: PortNum.aeriemedApp, payload: payload);
      expect(f.length, greaterThan(payload.length));
      // payload bytes appear verbatim inside the MeshPacket.Data.payload field
      expect(_contains(f, payload), isTrue);
    });
  });

  group('loopback mesh transport', () {
    test('hub fans a write from one node out to the others verbatim', () async {
      final hub = LoopbackHub();
      final a = LoopbackTransport(hub);
      final b = LoopbackTransport(hub);
      final c = LoopbackTransport(hub);
      await a.connect();
      await b.connect();
      await c.connect();

      final atB = <int>[];
      final atC = <int>[];
      b.incoming.listen(atB.addAll);
      c.incoming.listen(atC.addAll);

      final frame = toRadioData(
        channel: 0,
        portnum: PortNum.aeriemedApp,
        payload: encodeAerieMed(const AmSos(
          missionCode: 'ALPHA7',
          nodeId: 'n1',
          callsign: 'R4',
          lat: 10.0,
          lng: 20.0,
        )),
      );
      await a.send(frame);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(atB, frame);
      expect(atC, frame);
    });

    test('a lone LoopbackTransport echoes writes back to itself', () async {
      final t = LoopbackTransport();
      await t.connect();
      final seen = <int>[];
      t.incoming.listen(seen.addAll);
      await t.send(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(seen, [1, 2, 3]);
    });
  });
}
