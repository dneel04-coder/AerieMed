import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'meshtastic_frame.dart';
import 'lora_transport.dart';

/// Bluetooth LE link to a Meshtastic radio — the mobile path (iOS / Android).
/// Built on `universal_ble` (Apache-2.0).
///
/// BLE has no `0x94 0xC3` stream framing: each `FromRadio` read returns exactly
/// one protobuf message (or empty when the queue is drained), and each
/// `ToRadio` write takes exactly one. On every `FromNum` notification we drain
/// `FromRadio` until it returns empty.
class BleLoraTransport implements LoraTransport {
  final String deviceId;

  static final String _svc = BleUuidParser.string(kMeshtasticBleService);
  static final String _toRadioC = BleUuidParser.string(kMeshtasticToRadioChar);
  static final String _fromRadioC = BleUuidParser.string(kMeshtasticFromRadioChar);
  static final String _fromNumC = BleUuidParser.string(kMeshtasticFromNumChar);

  StreamSubscription<Uint8List>? _fromNumSub;
  StreamSubscription<bool>? _connSub;
  bool _draining = false;
  bool _ready = false;

  final _incoming = StreamController<Uint8List>.broadcast();
  final _state = StreamController<LoraLinkState>.broadcast();
  LoraLinkState _current = LoraLinkState.disconnected;

  BleLoraTransport(this.deviceId);

  /// Scan for advertising Meshtastic radios. Caller sets [UniversalBle.onScanResult]
  /// or listens [UniversalBle.scanStream]; remember to [stopScan].
  static Future<void> startScan() => UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [kMeshtasticBleService]),
      );

  static Future<void> stopScan() => UniversalBle.stopScan();

  static Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  static Future<AvailabilityState> bluetoothAvailability() =>
      UniversalBle.getBluetoothAvailabilityState();

  static Stream<AvailabilityState> get availabilityStream => UniversalBle.availabilityStream;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;
  @override
  Stream<LoraLinkState> get state => _state.stream;
  @override
  LoraLinkState get currentState => _current;

  void _set(LoraLinkState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  @override
  Future<void> connect() async {
    _set(LoraLinkState.connecting);
    try {
      _connSub = UniversalBle.connectionStream(deviceId).listen((connected) {
        if (!connected && _ready) _set(LoraLinkState.disconnected);
      });

      await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
      try {
        await UniversalBle.requestMtu(deviceId, 512);
      } catch (_) {/* non-fatal */}

      final services = await UniversalBle.discoverServices(deviceId);
      final hasService = services.any((s) => s.uuid == _svc);
      if (!hasService) {
        throw StateError('not a Meshtastic device (service $_svc missing)');
      }

      _fromNumSub = UniversalBle.characteristicValueStream(deviceId, _fromNumC)
          .listen((_) => _drain());
      await UniversalBle.subscribeNotifications(deviceId, _svc, _fromNumC);

      _ready = true;
      _set(LoraLinkState.connected);
      await _drain(); // pick up anything already queued
    } catch (_) {
      _set(LoraLinkState.error);
      await disconnect();
      rethrow;
    }
  }

  Future<void> _drain() async {
    if (_draining || !_ready) return;
    _draining = true;
    try {
      while (true) {
        final value = await UniversalBle.read(deviceId, _svc, _fromRadioC);
        if (value.isEmpty) break;
        if (!_incoming.isClosed) _incoming.add(value);
      }
    } catch (_) {
      // transient read error — next FromNum notification retries
    } finally {
      _draining = false;
    }
  }

  @override
  Future<void> send(Uint8List message) async {
    if (!_ready) return;
    await UniversalBle.write(deviceId, _svc, _toRadioC, message, withoutResponse: false);
  }

  @override
  Future<void> disconnect() async {
    _ready = false;
    await _fromNumSub?.cancel();
    _fromNumSub = null;
    await _connSub?.cancel();
    _connSub = null;
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {}
    _set(LoraLinkState.disconnected);
    if (!_incoming.isClosed) await _incoming.close();
    if (!_state.isClosed) await _state.close();
  }
}
