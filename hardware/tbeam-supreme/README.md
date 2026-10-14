# LILYGO T-Beam Supreme — off-grid LoRa link

The T-Beam Supreme is the radio ResQruck / AerieMed uses for low-bandwidth data
transmission when cellular and wifi are unavailable (see `lib/lora/`). It runs **stock
Meshtastic firmware** — there is no custom firmware to build. This directory holds the
one-time flashing and configuration steps plus the shared channel definition.

## Hardware

- LILYGO **T-Beam Supreme** (ESP32-S3 + Semtech SX1262 LoRa + u-blox MIA-M10Q GPS).
  Meshtastic hardware target: **`tbeam-s3-core`**.
- 18650 Li-ion cell (button-top, protected).
- Antenna matched to your region's band — **915 MHz** (US / `US` region) or **868 MHz**
  (EU / `EU_868`). Never power the radio without an antenna attached.
- USB-C cable for flashing and for the desktop / Command Console serial link.

## 1. Flash Meshtastic

Pick one method.

### Web flasher (easiest)
1. Chrome or Edge → <https://flasher.meshtastic.org>.
2. Connect the T-Beam by USB-C, select device **T-Beam S3 Core**, channel **stable**.
3. Flash. Use "Full erase and install" the first time.

### CLI
```bash
pip install --upgrade "meshtastic[cli]" esptool
# with the board in bootloader mode (hold BOOT, tap RST, release BOOT):
esptool --chip esp32s3 erase_flash
# then flash the latest stable firmware.bin / .uf2 per Meshtastic docs for tbeam-s3-core
```

## 2. Apply the AerieMed configuration

Everything below is device configuration, not firmware. Do it once per radio.

```bash
# region — set to match your antenna / local regulations
meshtastic --set lora.region US
meshtastic --set device.role CLIENT

# GPS on, position beacon every 120 s (see "Duty cycle" below before lowering this)
meshtastic --set position.gps_mode ENABLED
meshtastic --set position.position_broadcast_secs 120
meshtastic --set position.position_broadcast_smart_enabled true

# the shared AerieMed channel on index 0 (primary)
meshtastic --ch-index 0 --ch-set name AerieMed
meshtastic --ch-index 0 --ch-set psk base64:REPLACE_WITH_TEAM_KEY
meshtastic --ch-index 0 --ch-set uplink_enabled false --ch-set downlink_enabled false
```

Or import the whole config in one shot:

```bash
meshtastic --configure hardware/tbeam-supreme/config.yaml
```

`config.yaml` in this directory is a template with the PSK redacted.

## 3. The team channel key (PSK)

The channel PSK is the **shared secret** that authenticates and encrypts all AerieMed
mesh traffic. Every radio on the team must carry the identical key.

- Generate a 256-bit key: `openssl rand -base64 32`
- Distribute it out of band (in person, or via the existing encrypted team channel).
  **Do not commit the real key.** `config.yaml` keeps the placeholder.
- The same key must be entered in the app: Tac Map → Radio settings → Channel key.
- Rotating the key means re-configuring every radio and every app install.

## 4. How the app talks to the radio

- **Phone / tablet:** Bluetooth LE (`lib/lora/ble_lora_transport.dart`). Pair from the
  OS Bluetooth settings first (default PIN `123456`), then connect in the app.
- **Desktop / Command Console:** USB-C serial (`lib/lora/serial_lora_transport.dart`).
  On Linux the user must be in the `dialout` group
  (`sudo usermod -aG dialout $USER`, then re-login).

The app uses Meshtastic's native position / node-info frames for locations, and a
private port number (`260`, see `lib/lora/aeriemed_codec.dart`) for map markers, zones,
SOS, MCI triage tallies, and short text.

## Duty cycle

LoRa airtime is regulated. A 120 s position beacon per radio is safe for teams up to
~10 radios on the default LongFast modem preset. Below 60 s, or with a larger team,
you will hit regional duty-cycle limits and messages will be dropped or delayed —
raise `position_broadcast_secs` and rely on smart-position instead.
