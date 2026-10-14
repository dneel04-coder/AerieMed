import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resqruck/lora/aeriemed_codec.dart';

void main() {
  group('AerieMed codec round-trip', () {
    test('POS', () {
      const m = AmPos(
        missionCode: 'ALPHA7',
        nodeId: 'dev-1234',
        callsign: 'MEDIC1',
        lat: 37.7749295,
        lng: -122.4194155,
        battery: 84,
        status: 'Active',
      );
      final decoded = decodeAerieMed(encodeAerieMed(m)) as AmPos;
      expect(decoded.missionCode, 'ALPHA7');
      expect(decoded.callsign, 'MEDIC1');
      expect(decoded.lat, closeTo(37.7749295, 1e-7));
      expect(decoded.lng, closeTo(-122.4194155, 1e-7));
      expect(decoded.battery, 84);
      expect(decoded.status, 'Active');
    });

    test('SOS', () {
      const m = AmSos(
        missionCode: 'ALPHA7',
        nodeId: 'dev-1',
        callsign: 'R4',
        lat: -33.8688,
        lng: 151.2093,
        resolved: true,
      );
      final d = decodeAerieMed(encodeAerieMed(m)) as AmSos;
      expect(d.resolved, true);
      expect(d.lat, closeTo(-33.8688, 1e-6));
      expect(d.lng, closeTo(151.2093, 1e-6));
    });

    test('MARKER upsert + delete', () {
      const up = AmMarkerUpsert(
        missionCode: 'BR2',
        id: '8b1f0c2e-aa',
        type: 5,
        label: 'Drop Point 3',
        lat: 45.0,
        lng: -100.5,
        placedBy: 'IC',
      );
      final du = decodeAerieMed(encodeAerieMed(up)) as AmMarkerUpsert;
      expect(du.id, '8b1f0c2e-aa');
      expect(du.type, 5);
      expect(du.label, 'Drop Point 3');

      const del = AmMarkerDelete(missionCode: 'BR2', id: '8b1f0c2e-aa');
      final dd = decodeAerieMed(encodeAerieMed(del)) as AmMarkerDelete;
      expect(dd.id, '8b1f0c2e-aa');
    });

    test('ZONE with polygon', () {
      const z = AmZoneUpsert(
        missionCode: 'BR2',
        id: 'z-1',
        type: 2,
        label: 'Hot',
        points: [(lat: 1.0, lng: 2.0), (lat: 3.0, lng: 4.0), (lat: 5.5, lng: 6.5)],
      );
      final d = decodeAerieMed(encodeAerieMed(z)) as AmZoneUpsert;
      expect(d.points.length, 3);
      expect(d.points[2].lat, closeTo(5.5, 1e-7));
      expect(d.points[2].lng, closeTo(6.5, 1e-7));
    });

    test('TRIAGE', () {
      const t = AmTriage(
        missionCode: 'MCI1',
        nodeId: 'n1',
        immediate: 3,
        delayed: 7,
        minor: 12,
        expectant: 1,
      );
      final d = decodeAerieMed(encodeAerieMed(t)) as AmTriage;
      expect([d.immediate, d.delayed, d.minor, d.expectant], [3, 7, 12, 1]);
    });

    test('short TEXT stays one frame', () {
      final frames = encodeText(missionCode: 'A1', msgId: 'deadbeef', from: 'C1', body: 'RTB now');
      expect(frames.length, 1);
      final d = decodeAerieMed(frames.single) as AmText;
      expect(d.body, 'RTB now');
    });

    test('oversized message throws', () {
      final huge = AmMarkerUpsert(
        missionCode: 'A1',
        id: 'x',
        type: 1,
        label: 'L' * 250,
        lat: 0,
        lng: 0,
      );
      expect(() => encodeAerieMed(huge), throwsFormatException);
    });
  });

  group('text chunking + reassembly', () {
    test('long body splits and rejoins in order', () {
      final body = List.generate(40, (i) => 'segment$i').join(' ');
      final frames = encodeText(missionCode: 'ALPHA7', msgId: 'abcd1234', from: 'DISPATCH', body: body);
      expect(frames.length, greaterThan(1));

      final reasm = TextReassembler();
      ({String from, String body})? result;
      for (final f in frames) {
        final msg = decodeAerieMed(f) as AmTextChunk;
        result = reasm.add(msg) ?? result;
      }
      expect(result, isNotNull);
      expect(result!.from, 'DISPATCH');
      expect(result.body, body);
    });

    test('every chunk is within the payload cap', () {
      final body = 'x' * 4000;
      final frames = encodeText(missionCode: 'ALPHA7', msgId: 'abcd1234', from: 'D', body: body);
      for (final f in frames) {
        expect(f.length, lessThanOrEqualTo(kMaxPayload));
      }
    });

    test('reassembly tolerates out-of-order arrival', () {
      final body = 'The quick brown fox ' * 30;
      final frames = encodeText(missionCode: 'A', msgId: 'ff00ff00', from: 'F', body: body)
          .map((f) => decodeAerieMed(f) as AmTextChunk)
          .toList()
          .reversed
          .toList();
      final reasm = TextReassembler();
      ({String from, String body})? result;
      for (final c in frames) {
        result = reasm.add(c) ?? result;
      }
      expect(result!.body, body);
    });
  });

  test('unknown codec version is rejected', () {
    final bad = Uint8List.fromList([0xE0, 0x00]); // version 7
    expect(() => decodeAerieMed(bad), throwsFormatException);
  });
}
