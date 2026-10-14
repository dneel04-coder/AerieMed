import 'dart:async';
import 'dart:typed_data';

/// Physical link to a Meshtastic radio. Implementations:
///   - [LoopbackTransport]           — tests / in-app demo
///   - `SerialLoraTransport`         — desktop USB-serial (flutter_libserialport)
///   - `BleLoraTransport`            — mobile Bluetooth LE (flutter_blue_plus)
///
/// A transport exchanges **whole, unframed protobuf messages** with the radio.
/// The serial transport handles the `0x94 0xC3` stream framing internally; the
/// BLE transport has no framing to do. Message semantics live in
/// `lora_service.dart`.
abstract class LoraTransport {
  /// One complete `FromRadio` protobuf message per event.
  Stream<Uint8List> get incoming;

  Stream<LoraLinkState> get state;
  LoraLinkState get currentState;

  Future<void> connect();
  Future<void> disconnect();

  /// Write one unframed `ToRadio` protobuf message to the radio.
  Future<void> send(Uint8List message);
}

enum LoraLinkState { disconnected, connecting, connected, error }

/// A transport that echoes everything written back to [incoming]. Wire two of
/// these to a shared [LoopbackHub] to simulate a two-node mesh in tests.
class LoopbackTransport implements LoraTransport {
  final LoopbackHub? _hub;
  final _incoming = StreamController<Uint8List>.broadcast();
  final _state = StreamController<LoraLinkState>.broadcast();
  LoraLinkState _current = LoraLinkState.disconnected;

  LoopbackTransport([this._hub]) {
    _hub?._register(this);
  }

  @override
  Stream<Uint8List> get incoming => _incoming.stream;
  @override
  Stream<LoraLinkState> get state => _state.stream;
  @override
  LoraLinkState get currentState => _current;

  void _set(LoraLinkState s) {
    _current = s;
    _state.add(s);
  }

  @override
  Future<void> connect() async => _set(LoraLinkState.connected);

  @override
  Future<void> disconnect() async {
    _set(LoraLinkState.disconnected);
    await _incoming.close();
    await _state.close();
  }

  @override
  Future<void> send(Uint8List message) async {
    if (_hub != null) {
      _hub._deliverExcept(this, message);
    } else {
      _incoming.add(message); // pure echo
    }
  }

  void deliver(Uint8List message) => _incoming.add(message);
}

/// Fans bytes written by any registered [LoopbackTransport] out to all the
/// others — a stand-in mesh for integration tests.
class LoopbackHub {
  final List<LoopbackTransport> _nodes = [];
  void _register(LoopbackTransport t) => _nodes.add(t);
  void _deliverExcept(LoopbackTransport from, Uint8List bytes) {
    for (final n in _nodes) {
      if (!identical(n, from)) n.deliver(bytes);
    }
  }
}
