# OpenCog

An iPhone and iPad app for indoor training on the **Van Rysel D100 (Zwift Cog edition)**. It works with
**Zwift Click v2** virtual shifters and shows live heart rate from a **Garmin watch** (or any Bluetooth heart-rate
broadcaster).

The app acts as the gearbox. It keeps the current virtual gear, reads the Click buttons, and tells the trainer
which gear ratio, grade or ERG target to simulate, using the Zwift protocol described in
[docs/BLUETOOTH_PROTOCOL.md](docs/BLUETOOTH_PROTOCOL.md).

## Features

- **Virtual shifting** with Zwift's 24-gear table. Use the Click paddles or the on-screen buttons. Holding a paddle
  keeps shifting.
- **Gears (SIM) mode** with an adjustable grade from −10 % to +15 %. The trainer can't simulate descents, so on a
  negative grade it rides as flat and the app shows the extra speed on screen.
- **ERG mode** with a target from 50 to 600 W, adjusted in 5, 10 or 25 W steps. In ERG mode the paddles change the
  target by ±5 W.
- **Live dashboard** showing power (tinted by FTP zone), heart rate (tinted by HR zone), estimated cadence, virtual
  speed, distance, average power, Normalized Power with TSS, and energy. A rolling 5-minute power and heart-rate
  chart sits underneath.
- **Ride recording** with auto-pause. History is saved on the device (SwiftData) and each ride has power and
  heart-rate charts.
- **TCX export** with power, heart rate, cadence and distance, for Strava, Garmin Connect, TrainingPeaks or
  intervals.icu.
- **Adaptive layout.** iPhone shows one column with the start/pause controls pinned at the bottom. iPad shows
  metrics and charts on the left and trainer controls on the right. Light and dark mode, Dynamic Type and
  VoiceOver labels are supported.
- **Background riding**: the `bluetooth-central` background mode and state restoration keep the session alive.
  The screen stays awake while a ride is in progress.

## Requirements

- Xcode 16 or later. The project uses folder-synchronized groups, so files added to `OpenCog/` show up
  automatically.
- iOS / iPadOS 17 or later.
- A **real device**. The iOS Simulator has no Bluetooth LE.

## Getting started

1. Open `OpenCog.xcodeproj`.
2. Select the **OpenCog** target → *Signing & Capabilities* and choose your team. If needed, change the bundle
   identifier (`com.opencog.OpenCog`).
3. Run on your iPhone or iPad. Allow Bluetooth access when asked.
4. Close Zwift (and any other trainer app) on all devices, so the trainer and Clicks are free to connect.
5. Open the **Devices** tab:
   - The trainer (`VANRYSEL-HT-xxxx`) and both Click halves connect automatically. Press a Click button to wake it.
   - **Garmin heart rate:** on the watch, turn on **Broadcast Heart Rate**. On most models, hold *MENU* (or open the
     controls menu) and choose *Broadcast Heart Rate*. Some models put it under *Settings › Sensors & Accessories ›
     Wrist Heart Rate*. The watch then appears under *Heart Rate*; tap it once. The app remembers it and
     reconnects next time. The watch has to broadcast over Bluetooth, which most Garmin models from 2019 onward do.
6. Go to **Settings** and enter your weight, bike weight, FTP, max heart rate and chainring size. Cadence is
   estimated from flywheel speed, chainring and the 14T Zwift Cog, so the chainring size matters.

## Installing from Windows (no Mac)

GitHub Actions builds the app on a Mac in the cloud on every push (`.github/workflows/ios.yml`). It produces an
unsigned `OpenCog.ipa` file, which you sign and install with your own Apple ID.

1. On GitHub, open **Actions → iOS build**, pick the latest green run, and download the **OpenCog-ipa** artifact.
   Unzip it to get `OpenCog.ipa`. To start a fresh build, use *Run workflow*.
2. On Windows, install **iTunes** and **iCloud**. Use the versions from apple.com, not the Microsoft Store ones.
   Then install **[Sideloadly](https://sideloadly.io)**.
3. On the iPhone, turn on **Developer Mode** (Settings → Privacy & Security → Developer Mode). The phone restarts.
4. Connect the iPhone by USB and trust the computer. In Sideloadly, drop in `OpenCog.ipa`, enter your Apple ID,
   and press **Start**. A free Apple ID works.
5. On the iPhone, go to Settings → General → VPN & Device Management and **trust** your Apple ID's developer
   profile. Then open OpenCog.

With a free Apple ID the install lasts **7 days**. After that, sideload it again; your rides and settings are
kept. Sideloadly can refresh it automatically over Wi-Fi, and AltStore is an alternative that does the same.
A paid Apple Developer account extends this to a year.

## Tests

The GitHub workflow also runs the unit tests on an iPhone simulator. On a Mac, run them with ⌘U. They check the protocol encoder and decoder against the byte captures in the
protocol doc, plus the Click relay filter, physics and ride metrics.

## Zwift Click button map

| Button | Gears mode | ERG mode |
|---|---|---|
| Right shift paddle | Harder gear | +5 W |
| Left shift paddle | Easier gear | −5 W |
| D-pad up / down | Grade ±0.5 % | ±10 W |
| A | Start / pause / resume ride | same |
| Y | Switch Gears ↔ ERG | same |

The left Click half also relays the right half's presses. The app accepts each button only from the half that
physically has it, so nothing shifts twice, and it still works when only one half is connected.

## Project layout

```
OpenCog/
  App/            App entry point and tab root
  Protocol/       Protobuf varints, Zwift commands/parsers, gear table, Click input, HR measurement
  Bluetooth/      CoreBluetooth central: discovery, connect, RideOn handshake, reconnects, write queue
  Model/          RideEngine (gearbox, 1 Hz control loop, recording), physics, metrics, settings, SwiftData model, TCX
  Views/          Ride dashboard, Devices, History, Settings
OpenCogTests/     Protocol, Click input, physics and metrics tests
docs/             Bluetooth protocol reference and original capture notes
```

How the parts fit together:

- `BluetoothManager` connects as a central to the trainer, the two Click halves and the HR monitor. For the Zwift
  devices it enables notifications on Async and Sync TX, writes `RideOn`, and marks the device ready when the reply
  arrives. It redoes the handshake after every reconnect.
- `RideEngine` holds the gear, grade, mode and ERG target. When the trainer becomes ready it sends Simulation and
  Physical (or ERG). After that it resends the active mode every 2 s and sends Physical again whenever the gear or
  a weight changes.
- Virtual speed comes from power, grade and total mass using the same road model as the trainer (CwA 0.51,
  Crr 0.004). Cadence is `flywheel m/s ÷ (chainring/cog × wheel circumference) × 60`.

## Status

The protocol layer follows the verified captures in `docs/`. The app has not yet been ride-tested end to end on
the hardware, so please report anything that behaves differently on your trainer or firmware.
