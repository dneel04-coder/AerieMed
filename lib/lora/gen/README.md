# `lib/lora/gen/` — generated Meshtastic protobuf classes

This folder is where `protoc`-generated Dart classes for the Meshtastic protocol
belong. **It is currently empty on purpose** — the initial LoRa foundation ships
with a small hand-rolled wire codec (`../proto_wire.dart` + `../meshtastic_frame.dart`)
that reads only the fields AerieMed touches. That keeps the first cut buildable
without adding a code-generation step to a repo that otherwise has none.

Replace the hand-rolled subset with real generated code when moving past the bench
stage:

## One-time generation

```bash
dart pub global activate protoc_plugin
git clone --depth 1 https://github.com/meshtastic/protobufs /tmp/meshtastic-protobufs

protoc \
  --dart_out=lib/lora/gen \
  --proto_path=/tmp/meshtastic-protobufs \
  /tmp/meshtastic-protobufs/meshtastic/mesh.proto \
  /tmp/meshtastic-protobufs/meshtastic/portnums.proto \
  /tmp/meshtastic-protobufs/meshtastic/config.proto \
  /tmp/meshtastic-protobufs/meshtastic/channel.proto \
  /tmp/meshtastic-protobufs/meshtastic/telemetry.proto
```

Commit the generated `*.pb*.dart` files (the repo has no `build_runner` step, so
generated code is checked in, same as any other source).

## Then

- Add `protobuf: ^3.x` to `pubspec.yaml` (`protoc_plugin` pins the compatible
  runtime — verify against the SDK-pinned `meta` version first, see the
  `pdfrx_engine` note in `pubspec.yaml`).
- Rewrite `meshtastic_frame.dart` to use `ToRadio`/`FromRadio`/`MeshPacket`/`Data`
  from here instead of `proto_wire.dart`. Keep the 4-byte stream framing
  (`0x94 0xC3` + length) — that is not protobuf and stays as-is.
- Pin the firmware version this was generated against in this README.
