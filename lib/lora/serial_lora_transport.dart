import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'meshtastic_frame.dart';
import 'lora_transport.dart';

/// USB-serial link to a Meshtastic radio — the desktop path (Windows / macOS /
/// Linux). Applies the `0x94 0xC3` stream framing that the serial Client API
/// uses; delivers whole unframed protobuf messages upward.
///
/// Linux note: the user must be in the `dialout` group to open the port.
class SerialLoraTransport implements LoraTransport {
  final String portName;
  final int baudRate;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readSub;
  final _decoder = FrameDecoder();

  final _incoming = StreamController<Uint8List>.broadcast();
  final _state = StreamController<LoraLinkState>.broadcast();
  LoraLinkState _current = LoraLinkState.disconnected;

  SerialLoraTransport(this.portName, {this.baudRate = 115200});

  /// Serial ports that look like a plausible radio. The caller still picks one.
  static List<String> availablePorts() {
    try {
      return SerialPort.availablePorts;
    } catch (_) {
      return const [];
    }
  }

  /// Best-effort human label for a port (USB product string when exposed).
  static String describe(String name) {
    try {
      final p = SerialPort(name);
      final desc = p.description;
      p.dispose();
      return desc == null || desc.isEmpty ? name : '$name — $desc';
    } catch (_) {
      return name;
    }
  }

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
      final port = SerialPort(portName);
      if (!port.openReadWrite()) {
        port.dispose();
        throw SerialPortError('cannot open $portName (in use, or not permitted)');
      }
      port.config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);
      _port = port;

      final reader = SerialPortReader(port);
      _reader = reader;
      _readSub = reader.stream.listen(
        _onBytes,
        onError: (_) => _fail(),
        cancelOnError: true,
      );
      _set(LoraLinkState.connected);
    } catch (_) {
      _set(LoraLinkState.error);
      rethrow;
    }
  }

  void _onBytes(Uint8List chunk) {
    for (final message in _decoder.add(chunk)) {
      if (!_incoming.isClosed) _incoming.add(message);
    }
  }

  void _fail() {
    _set(LoraLinkState.error);
    unawaited(disconnect());
  }

  @override
  Future<void> send(Uint8List message) async {
    final port = _port;
    if (port == null) return;
    port.write(encodeFrame(message));
  }

  @override
  Future<void> disconnect() async {
    await _readSub?.cancel();
    _readSub = null;
    _reader?.close();
    _reader = null;
    try {
      _port?.close();
    } catch (_) {}
    _port?.dispose();
    _port = null;
    _set(LoraLinkState.disconnected);
    await _incoming.close();
    await _state.close();
  }
}
