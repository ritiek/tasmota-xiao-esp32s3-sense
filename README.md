# Tasmota for the Seeed XIAO ESP32S3 Sense (OV3660, PDM mic, 8 MB)

Custom Tasmota v16.0.0 build for this board with camera, microphone, SD card
driver, Berry, TFLite Micro and BLE compiled in, plus a backup of the firmware
it shipped with.

## Quick start

```sh
nix run .#build          # ~45 min cold, ~8 min incremental; output in build/out/
nix run .#flash          # erase + flash build/out/*.factory.bin via $XIAO_HOST (resets settings)
```

For an upgrade that keeps settings, upload `build/out/tasmota32s3-xiao-sense.bin`
in the web UI (Firmware Upgrade). That path was tested: it boots into the
locally built safeboot image and back.

## Why a custom build

There is no off-the-shelf Tasmota image that covers this board:

| Image | Problem |
|---|---|
| `tasmota32s3.bin` (official) | Built for quad PSRAM; no camera, no I2S |
| `tasmota32-webcam.bin` (official) | Classic ESP32 only |
| `tasmota32s3-qio_opi.factory.bin` (unofficial, tasmota/install) | No I2S mic, no TFLite. Camera fails on this board: `CAM: Init failed !frame on time` |

The unofficial image was flashed and tested first; evidence is in
`docs/offtheshelf/`. Its camera failure is an esp32-camera bug, fixed here by
patch 0001.

## Layout

| Path | What it is |
|---|---|
| `flake.nix` | Pins Tasmota v16.0.0, nixpkgs and decode-config. Packages pioarduino 6.2.0 (Tasmota's PlatformIO fork) in an FHS env. Apps `build` and `flash` |
| `firmware/platformio_override.ini` | Build env `tasmota32s3-xiao-sense`: board `esp32s3-qio_opi`, 8 MB, I2S audio, TFLite + ESP-NN |
| `firmware/user_config_override.h` | WiFi, GPIO template, camera/SD/BLE defines, first-boot command list |
| `firmware/partitions_8MB.csv` | Upstream 8 MB layout with the file system already filling the flash |
| `firmware/patches/` | Two fixes to Tasmota's webcam driver (below) |
| `ml/` | TFLite smoke test (sine model + Berry script) |
| `docs/` | Test evidence: mic spectrogram, TFL log, off-the-shelf test |
| `backup/` | The original firmware, full flash dump and decoded config. See `backup/README.md` |

The build is not a pure Nix derivation: PlatformIO downloads its toolchain
into `build/platformio`. Sources and versions are pinned, though.

## Patches and fixes

1. `0001-webcam-disable-psram-dma.patch`: with PSRAM DMA on, esp32-camera drops
   every OV3660 JPEG frame as missing its end marker
   ([espressif/esp32-camera#853](https://github.com/espressif/esp32-camera/issues/853)),
   so the camera initialises but never returns a frame. The patch calls
   `esp_camera_set_psram_mode(false)` before init.
2. `0002-webcam-start-stream-server-on-network-up.patch`: the port 81 stream
   server is started at `FUNC_INIT`, where WiFi is still down and the call
   bails out. It only came up once someone opened the web UI. The patch
   starts it on `FUNC_NETWORK_UP`.
3. Partition table: upstream's 8 MB CSV stops the file system at 6 MB, so
   Berry grows it on first boot and restarts. That restart threw away most of
   `USER_BACKLOG`. The local CSV fills the flash from the start.
4. `USER_BACKLOG` sets every camera value explicitly, because the webcam
   driver writes its own defaults on first boot in an order that races the
   backlog.

## Pins (GPIO template)

| Function | GPIO |
|---|---|
| Camera XCLK, SIOD, SIOC | 10, 40, 39 |
| Camera D1..D8 | 15, 17, 18, 16, 14, 12, 11, 48 |
| Camera VSYNC, HREF, PCLK | 38, 47, 13 |
| microSD CS, SCK, MISO, MOSI | 21, 7, 8, 9 |
| PDM mic CLK (I2S WS), DATA (I2S DIN) | 42, 41 |
| BOOT button | 0 |

The user LED is also on GPIO21 (active low), so it flickers with SD access and
is not assigned. The community template on templates.blakadder.com puts SD CS on
GPIO3, which is wrong for the stock board.

## Defaults applied on first boot

`SetOption127 1` (WiFi no-sleep), `Sleep 0`,
`SetOption146 1` (chip temperature), `WcStream 1`, `WcResolution 15`
(1600x1200), `WcFlip 1`, `WcMirror 0`, `WcBrightness 1`, `WcSaturation -2`,
`WcContrast 0`, `I2SConfig {"Rx":{"Mode":1,"SampleRate":16000}}`.

- The OV3660 sits upside down on this module, hence `WcFlip 1`.
- Brightness +1 and saturation -2 are Espressif's CameraWebServer defaults for
  the OV3660. Saturation 0 gives a green cast.
- WiFi no-sleep plus `Sleep 0` takes UXGA from about 3 to 8 fps. The chip runs
  at 50-57 C while streaming; Seeed recommends the heat sink.

## Endpoints

| URL | What |
|---|---|
| `http://192.168.1.50/` | Web UI |
| `http://192.168.1.50:81/stream` | MJPEG stream (total ~8 fps at UXGA, shared between viewers) |
| `http://192.168.1.50/snapshot.jpg` | Single frame (~60 KB at UXGA) |
| `rtsp://192.168.1.50:8554/mjpeg/1` | RTSP, after `WcRtsp 1` (restarts the board) |
| `http://192.168.1.50:82/stream.webm` | Live mic as Opus, after `I2SStream 1` |

HTTP API calls need a `Referer: http://192.168.1.50/` header, otherwise the
board returns an empty reply.

## Feature status

| Feature | Status | How it was checked |
|---|---|---|
| Camera | Works | OV3660 detected; UXGA ~8 fps, QXGA (`WcResolution 19`) ~5 fps |
| RTSP | Works | ffmpeg read 1600x1200 MJPEG from `rtsp://.../mjpeg/1` |
| Microphone | Works | `I2SRec2 /mic.opus` recorded 10 s of 16 kHz Opus (spectrogram in `docs/mic/`); `I2SStream 1` served WebM on port 82 |
| TFLite Micro | Works | tflite-micro `hello_world` sine model matches `sin(x)` to ~0.03 (`docs/ml/sine_test.log`) |
| Berry | Works | Runs the TFL test |
| BLE | Works, off by default | `SetOption115 1` (restarts). Found a nearby device. Scanning cuts the camera stream to about a third, so it stays off |
| OTA upgrade | Works | Web UI upgrade through safeboot, settings kept |
| microSD | Driver in, card faulty | See below |

### microSD

The driver is built in (SPI on GPIO 7/8/9, CS 21) and mounts a FAT32 card at
boot with the log line `UFS: SDCard mounted`. The card in the slot (128 GB,
an old SBC root file system) reads fine, but any sustained write hangs it
until power is cut. This was tested with a bare Arduino sketch on the same
pins, at 4 and 20 MHz, with single- and multi-block writes. On a PC reader
the card shows zero manufacturer and OEM IDs (`APPSD`, an unregistered no-name
card), `f3probe` reports 0 bytes usable, and plain `dd` writes fail with I/O
errors. Details in `docs/sdcard.txt`.

To use the SD card: insert a known-good card, 32 GB or smaller, formatted
FAT32, and reboot.

### Machine learning

TFLite Micro runs Berry-driven models from the file system:

```sh
curl -H 'Referer: http://192.168.1.50/' -F ufsu=@ml/hello_world_float.tflite http://192.168.1.50/ufsu
curl -H 'Referer: http://192.168.1.50/' -F ufsu=@ml/sine_test.be http://192.168.1.50/ufsu
curl -H 'Referer: http://192.168.1.50/' -G --data-urlencode 'cmnd=Br load("/sine_test.be")' http://192.168.1.50/cm
```

Results appear in the console log. Models must be padded to a multiple of 8
bytes (the script does this). For keyword spotting, `TFL.begin("MIC", ...)`
uses the mic at 16 kHz, which is already configured; it needs a model trained
for it (for example with Edge Impulse). Tasmota has no face detection.

## Frigate

Frigate runs this camera as `cameras.xiao` on an RK3566 board: MJPEG from
`http://192.168.1.50:81/stream`, detection at 800x600 and 5 fps on the RK NPU.
