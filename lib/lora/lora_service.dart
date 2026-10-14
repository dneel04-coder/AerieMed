import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'aeriemed_codec.dart';
import 'meshtastic_frame.dart';
import 'lora_transport.dart';

/// How LoRa relates to the normal Supabase path.
enum RadioMode {
  /// Radio unused (today's behaviour).
  off,

  /// Use Supabase normally; fall back to the radio only while offline.
  auto,

  /// Ignore Supabase entirely — drills / comms blackout.
  radioOnly,
}

/// A node seen on the mesh (from Meshtastic NodeInfo/Position frames).
class MeshNode {
  final int num;
  String? userId;
  String? longName;
  String? shortName;
  double? lat;
  double? lng;
  DateTime lastHeard;
  MeshNode(this.num, {this.userId, this.longName, this.shortName, this.lat, this.lng, DateTime? lastHeard})
      : lastHeard = lastHeard ?? DateTime.now();
}

/// Inbound, decoded events the app cares about.
sealed class LoraEvent {
  const LoraEvent();
}

class LoraAppMessage extends LoraEvent {
  final AmMessage message;
  const LoraAppMessage(this.message);
}

class LoraNodePosition extends LoraEvent {
  final int nodeNum;
  final double lat;
  final double lng;
  const LoraNodePosition(this.nodeNum, this.lat, this.lng);
}

class LoraNodeIdentity extends LoraEvent {
  final MeshNode node;
  const LoraNodeIdentity(this.node);
}

/// Singleton coordinator. Mirrors the existing `*.instance` service style.
class LoraService {
  LoraService._();
  static final LoraService instance = LoraService._();

  LoraTransport? _transport;
  StreamSubscription<Uint8List>? _rxSub;
  StreamSubscription<LoraLinkState>? _stateSub;
  final _rng = Random();

  final _events = StreamController<LoraEvent>.broadcast();
  final _link = StreamController<LoraLinkState>.broadcast();
  Stream<LoraEvent> get events => _events.stream;
  Stream<LoraLinkState> get linkState => _link.stream;

  LoraLinkState _state = LoraLinkState.disconnected;
  LoraLinkState get state => _state;
  bool get isConnected => _state == LoraLinkState.connected && _configComplete;
  bool _configComplete = false;

  RadioMode mode = RadioMode.off;

  /// The primary Meshtastic channel index our team channel sits on (0 = primary).
  int channelIndex = 0;

  /// Set by the app from connectivity_plus. When false and [mode] is auto, the
  /// radio becomes an active transport.
  bool online = true;

  /// True when the radio should currently carry outbound app traffic.
  bool get radioActive =>
      isConnected && (mode == RadioMode.radioOnly || (mode == RadioMode.auto && !online));

  final Map<int, MeshNode> nodes = {};
  final TextReassembler _textReasm = TextReassembler();

  // ── outbound airtime throttle ────────────────────────────────────────────
  final List<_Outbound> _queue = [];
  Timer? _pump;
  DateTime _lastTx = DateTime.fromMillisecondsSinceEpoch(0);

  /// Minimum spacing between packets. LoRa airtime is regulated; 3 s is a safe
  /// floor for the LongFast preset. SOS jumps the queue but still respects this.
  Duration minTxSpacing = const Duration(seconds: 3);

  // ── lifecycle ────────────────────────────────────────────────────────────

  Future<void> attach(LoraTransport transport) async {
    await detach();
    _transport = transport;
    _configComplete = false;
    _rxSub = transport.incoming.listen(_onMessage, onError: (_) {});
    _stateSub = transport.state.listen(_onState);
    await transport.connect();
  }

  Future<void> detach() async {
    _pump?.cancel();
    _pump = null;
    _queue.clear();
    await _rxSub?.cancel();
    await _stateSub?.cancel();
    _rxSub = null;
    _stateSub = null;
    final t = _transport;
    _transport = null;
    if (t != null) {
      try {
        await t.send(toRadioDisconnect());
      } catch (_) {}
      await t.disconnect();
    }
    _setState(LoraLinkState.disconnected);
  }

  void _onState(LoraLinkState s) {
    _setState(s);
    if (s == LoraLinkState.connected) {
      // Kick the Meshtastic config handshake.
      _transport?.send(toRadioWantConfig(_rng.nextInt(0x7fffffff))).catchError((_) {});
    }
  }

  void _setState(LoraLinkState s) {
    _state = s;
    _link.add(s);
  }

  // ── inbound ──────────────────────────────────────────────────────────────

  /// One unframed `FromRadio` protobuf message from the transport.
  void _onMessage(Uint8List message) {
    final evt = parseFromRadio(message);
    if (evt == null) return;
    if (evt.configCompleteId != null) {
      _configComplete = true;
      _setState(LoraLinkState.connected);
      return;
    }
    if (evt.nodeInfo != null) {
      final ni = evt.nodeInfo!;
      final n = nodes.putIfAbsent(ni.num, () => MeshNode(ni.num));
      n
        ..userId = ni.userId ?? n.userId
        ..longName = ni.longName ?? n.longName
        ..shortName = ni.shortName ?? n.shortName
        ..lastHeard = DateTime.now();
      _events.add(LoraNodeIdentity(n));
      return;
    }
    if (evt.position != null && evt.position!.lat != null && evt.position!.lon != null) {
      final p = evt.position!;
      final n = nodes.putIfAbsent(p.fromNode, () => MeshNode(p.fromNode));
      n
        ..lat = p.lat
        ..lng = p.lon
        ..lastHeard = DateTime.now();
      _events.add(LoraNodePosition(p.fromNode, p.lat!, p.lon!));
      return;
    }
    final data = evt.data;
    if (data != null && data.portnum == PortNum.aeriemedApp) {
      _handleAppPayload(data.payload);
    }
  }

  void _handleAppPayload(Uint8List payload) {
    final AmMessage msg;
    try {
      msg = decodeAerieMed(payload);
    } catch (_) {
      return;
    }
    if (msg is AmTextChunk) {
      final joined = _textReasm.add(msg);
      if (joined != null) {
        _events.add(LoraAppMessage(AmText(
          missionCode: msg.missionCode,
          msgId: msg.msgId,
          from: joined.from,
          body: joined.body,
        )));
      }
      return;
    }
    _events.add(LoraAppMessage(msg));
  }

  // ── outbound ─────────────────────────────────────────────────────────────

  /// Queue an AerieMed message for transmission. No-op unless [radioActive].
  /// [priority] messages (SOS) are sent ahead of the rest and repeated [repeat]×.
  void send(AmMessage msg, {bool priority = false, int repeat = 1}) {
    if (!radioActive) return;
    final List<Uint8List> frames;
    try {
      frames = [toRadioData(channel: channelIndex, portnum: PortNum.aeriemedApp, payload: encodeAerieMed(msg))];
    } catch (_) {
      return; // oversized / unencodable
    }
    for (final f in frames) {
      for (var i = 0; i < repeat; i++) {
        final item = _Outbound(f, priority);
        if (priority) {
          _queue.insert(0, item);
        } else {
          _queue.add(item);
        }
      }
    }
    _ensurePump();
  }

  /// Queue free text, chunking as needed.
  void sendText({required String missionCode, required String from, required String body}) {
    if (!radioActive) return;
    final msgId = _rng.nextInt(0xffffffff).toRadixString(16).padLeft(8, '0');
    final frames = encodeText(missionCode: missionCode, msgId: msgId, from: from, body: body)
        .map((p) => toRadioData(channel: channelIndex, portnum: PortNum.aeriemedApp, payload: p));
    for (final f in frames) {
      _queue.add(_Outbound(f, false));
    }
    _ensurePump();
  }

  void _ensurePump() {
    _pump ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _drain());
    _drain();
  }

  void _drain() {
    if (_queue.isEmpty) {
      _pump?.cancel();
      _pump = null;
      return;
    }
    final t = _transport;
    if (t == null || !isConnected) return;
    if (DateTime.now().difference(_lastTx) < minTxSpacing) return;
    final item = _queue.removeAt(0);
    _lastTx = DateTime.now();
    t.send(item.framed).catchError((_) {});
  }
}

class _Outbound {
  final Uint8List framed;
  final bool priority;
  _Outbound(this.framed, this.priority);
}
