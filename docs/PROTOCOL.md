# Van Rysel D100 (Zwift Cog) + Zwift Click v2 — BLE protocol notes

> **Full protocol specification: see [BLUETOOTH_PROTOCOL.md](BLUETOOTH_PROTOCOL.md).** This file keeps the original analysis notes and test logs.

Captured from this hardware on 2026-10-10 with `bleak` on Windows.
Legend: ✅ observed on the real devices · ⚠️ sent/decoded but effect not yet confirmed on the bike · 📚 from SHIFTR source (github.com/doudar/SHIFTR, `DirConManager.cpp`)

## How the system works

```
 Zwift Click v2 (L) ─┐  button bitmaps                 gear ratio / grade / ERG
 Zwift Click v2 (R) ─┼──────────────►  YOUR APP  ──────────────────────────────►  D100 trainer
                     │   (BLE notify)               (Zwift protocol, BLE write)   (simulates the gear)
                     └── the halves also relay each other's presses
```

The Clicks never talk to the trainer. **The app is the gearbox**: it keeps the current gear (1–24), and on every shift
writes the new gear ratio to the trainer, which then applies resistance as if that chainring/cog combo were fitted.
The physical Zwift Cog stays on one cog; that's why its "virtual gear" range works.

Both device types use the same Zwift framing on three characteristics (base UUID `xxxxxxxx-19CA-4651-86E5-FA29DCDD09D1`):

| Char | Props | Role |
|---|---|---|
| `00000002` | notify | **async**: unsolicited events (buttons, riding data, battery) |
| `00000003` | write w/o response | **sync RX**: commands from the app |
| `00000004` | indicate | **sync TX**: responses to commands |

Every message = `1 byte opcode` + `protobuf` payload (plain wire format, varints = LEB128). No encryption on either device ✅.
`zwift_proto.py` has a ~60-line encoder/decoder; in Swift you can hand-roll the same (only varint + length-delimited needed).

---

## 1. Zwift Click v2 (pair) ✅

**Discovery**: advertises service `0xFC82` and manufacturer data with company ID **`0x094A`** (Zwift Inc).
First mfr byte = device type: **`0x0A` = right half, `0x0B` = left half** (also serial prefix `0A-…`/`0B-…`).
On iOS you don't get MAC addresses — use `CBAdvertisementDataManufacturerDataKey`: bytes `4A 09 0A …` (company ID is little-endian).
Clicks sleep after ~1 min idle; a button press wakes them.

GATT: service `0000FC82-…` contains the 3 Zwift chars above (+ `00000100/101/102`, unused here), plus Battery `0x180F`.

**Handshake**: subscribe to `…0002` and `…0004`, then write ASCII `RideOn` (`52 69 64 65 4F 6E`) to `…0003`.
Click answers `RideOn` on `…0004`. Buttons start streaming on `…0002`.

**Messages on async `…0002`:**

| Opcode | Meaning | Payload |
|---|---|---|
| `0x23` | button state | protobuf field 1 (`08`) varint = 32-bit bitmap, **bit = 0 means pressed** |
| `0x19` | battery | field 2 = % (e.g. `19 10 64` = 100 %), every ~5 s |
| `0x2A`, `0xFF` | device info / logs | ignore |

`0x23` frames repeat every ~90 ms while any button is held (use for auto-repeat); idle = `23 08 FF FF FF FF 0F`.

**Button bits** (identical to the Zwift Ride keymap):

| Bit | Mask | Button | Physically on |
|---|---|---|---|
| 0 | 0x0001 | D-pad Left | left (0B) |
| 1 | 0x0002 | D-pad Up | left |
| 2 | 0x0004 | D-pad Right | left |
| 3 | 0x0008 | D-pad Down | left |
| 4 | 0x0010 | A | right (0A) |
| 5 | 0x0020 | B | right |
| 6 | 0x0040 | Y | right |
| 7 | 0x0080 | Z | right |
| 8 | 0x0100 | **Shift (left big button) → shift down** | left |
| 12 | 0x1000 | **Shift (right big button) → shift up** | right |
| 9–11, 13–15 | | shift-down / powerup / on-off of a Zwift Ride; not present on Click v2 | |

⚠️ **Relay gotcha (observed)**: the left half also reports the right half's presses. If you connect both, accept each bit
only from its owner half (table above) or you'll double-shift. If only one half is connected, the relayed events
let a single connection serve both.

Example decode: `23 08 FF DF FF FF 0F` → varint `0xFFFFEFFF` → bit 12 clear → right shift pressed.

---

## 2. Van Rysel D100 trainer

Advertises as `VANRYSEL-HT-xxxx`. Decathlon model 355194, FW 0.108. Services:

| Service | Use |
|---|---|
| `00000001-19CA-…` **Zwift** | virtual shifting + SIM + ERG + riding data ✅ (handshake) |
| `0x1826` FTMS | standard control, alternative path |
| `0x1818` Cycling Power | power + crank revs |
| `0x180A` Device Info | |
| `F000FFC0-0451-…` | TI OAD **firmware update — never write** |
| `8CE5CC01-…`, `8CE5EE01-…` | unknown vendor, leave alone |

### Handshake ✅
Subscribe to `…0002` and `…0004`, write `RideOn` to `…0003`. Trainer replies `52 69 64 65 4F 6E 02 00` on `…0004`
and then sends **RidingData** on `…0002` once per second.

### RidingData (async, opcode `0x03`, 1 Hz) ✅ verified while riding
`03 08 22 10 00 18 E8 03 20 22 28 91 6D` → `1:34 2:0 3:488 4:34 5:13969` — protobuf:

| Field | Meaning (checked against FTMS at the same moments) |
|---|---|
| 1 | power W |
| 2 | cadence — **always 0 on the D100**, even while pedaling |
| 3 | flywheel speed in **m/s ×100** (488 = 17.6 km/h, matches FTMS) — real, not virtual speed |
| 4 | power W again (identical to field 1 in every frame) |
| 5 | unknown, always ≈ 28.6 × field 3 (another speed unit) |

Speed is the physical flywheel speed, so your app computes the *virtual* speed itself (physics from power, grade, weight).

**Cadence: the D100 sends none** ✅ checked: Zwift field 2 = 0, FTMS has no cadence flag, and Cycling Power
measurements only carry flags `0x0001` (power balance), with no crank data, even though the feature char claims it.
Estimate it from flywheel speed instead. The Zwift Cog keeps the physical gear fixed, so:

```
cadence_rpm = speed_mps / (chainring / 14 × 2.096) × 60      // 34T ring: 26.1 km/h ≈ 85 rpm
```

With 34T this tracked the requested 60/80/100 rpm steps (60/80/96 measured) ✅. Make the chainring a user setting.
FTMS Indoor Bike Data (~4 Hz) gives power + speed too and is a smoother source if you want it.

### Commands (sync RX, opcode `0x04` = HubCommand) 📚 + ✅ gear (no ack is sent; verify via power)

**Ride test, flat road, steady effort, 15 s per gear (averages after 5 s settle):**

| Gear | 12 | 8 | 4 | 8 | 12 | 16 | 20 | 12 |
|---|---|---|---|---|---|---|---|---|
| Power W | (warm-up) | 38 | 42 | 48 | 79 | 149 | 245 | 90 |
| Flywheel m/s | | 4.9 | 5.8 | 6.2 | 6.4 | 6.2 | 6.0 | 6.7 |

Shifts take effect within ~1–2 s. Below ~gear 8 the trainer seems to hit a minimum resistance floor (~40 W at this speed).

**Ride test 2 (dashboard, ~80 rpm, rider 75 kg):**

| SIM, gear 8 | −2 % | 0 % | +2 % | +4 % |
|---|---|---|---|---|
| Power W | 63 | 54–60 | 101 | 164 |

✅ Uphill grade works and scales roughly linearly. ⚠️ **Negative grades have no effect**: −2 % feels like flat, and FTMS also
reports an incline range of 0…6 %. Your app has to treat descents as flat (or fake them with a lower gear).

| ERG | 100 W @80 | 150 W @81 | 150 W @66 | 150 W @91 | 100 W @80 |
|---|---|---|---|---|---|
| Avg W (±sd) | 100 (±0) | 150 (±1) | 150 (±1) | 152 (±7) | 100 (±0) |

✅ ERG holds the target independent of cadence. Exiting ERG = just send SIM (`04 22`) + gear (`04 2A`) again ✅.
Note that during ERG the reported power is very smooth (±0–1 W), so it may be partly the target rather than the raw measurement.

| Command | Bytes | Fields |
|---|---|---|
| **Gear** (PhysicalParam, field 5) | `04 2A <len> 10 <gearRatio×10000> 20 <bikeKg×100> 28 <riderKg×100>` | ratio 2.40 → `10 C0 BB 01` |
| **SIM** (SimulationParam, field 4) | `04 22 <len> 10 <zigzag(grade%×100)> 18 <CdA×10000> 20 <Crr×100000>` | Zwift uses CdA 5100, Crr 400; optional field 1 = wind (zigzag) |
| **ERG** (field 3) | `04 18 <watts varint>` | `04 18 96 01` = 150 W |

Grade uses **zigzag** encoding (bit 0 = sign): +2.5 % → 250 → zigzag 500 → `F4 03`; −2.5 % → −250 → zigzag 499 → `F3 03`.
Gear ratio 0 → plain SIM without virtual shifting.

Zwift's 24 virtual gear ratios (gear 1 → 24):
`0.75 0.87 0.99 1.11 1.23 1.38 1.53 1.68 1.86 2.04 2.22 2.40 2.61 2.82 3.03 3.24 3.49 3.74 3.99 4.24 4.54 4.84 5.14 5.49`
(gear 12 = 2.40 ≈ 34×14 is a good start). Real examples sent ✅:

```
04 22 08 10 00 18 EC 27 20 90 03        flat road
04 2A 0A 10 C0 BB 01 20 E8 07 28 CC 3A  gear 12 (2.40), bike 10 kg, rider 75 kg
04 2A 09 10 CC 3A 20 E8 07 28 CC 3A     gear 1 (0.75)
04 2A 0A 10 F4 AC 03 20 E8 07 28 CC 3A  gear 24 (5.49)
```

Send SIM whenever grade changes (Zwift sends it ~1 Hz) and PhysicalParam on every shift.

### FTMS (alternative, standard) — capabilities read from device ✅
- Target settings `0x0000A00C`: resistance, power (ERG), **indoor bike simulation**, spin-down.
- Power range 50–600 W, resistance 0–100, inclination range 0–6.0 % reported.
- Indoor Bike Data at rest only carried speed + power flags (no cadence) → take cadence from Zwift RidingData or CPS crank revs.
- If you ever drop the Zwift protocol you can fake gears via FTMS sim grade, but the Zwift path is what the D100 is tuned for.

---

## 3. iOS (CoreBluetooth) checklist

1. `Info.plist`: `NSBluetoothAlwaysUsageDescription`; add `bluetooth-central` background mode if riding with the screen off.
2. Scan with `scanForPeripherals(withServices: nil)` and filter by: manufacturer data starts with `4A 09` + byte `0A`/`0B`
   (Clicks), name prefix `VANRYSEL` (trainer). Persist `peripheral.identifier` UUIDs for reconnects.
3. On each: discover services → `setNotifyValue(true)` on `…0002` and `…0004` → write `"RideOn"` to `…0003` with `.withoutResponse`.
4. Clicks: edge-detect bitmap changes, apply the owner filter, bit 12 → gear+1, bit 8 → gear−1 (clamp 1…24).
5. Trainer: on shift write PhysicalParam; on grade change write SimulationParam; for ERG write field 3.
6. Re-do the `RideOn` handshake after every reconnect; Clicks drop when they sleep.
7. Make sure the Zwift app on the phone/other devices is closed. Each device accepts only a limited number of connections.

## 4. Files here

| File | Purpose |
|---|---|
| `scan.py` | BLE advertisement scanner |
| `gatt_dump.py <addr>` | full GATT dump (`gatt_*.txt` outputs) |
| `click_sniff.py <addr> [s]` | raw Click logger; `analyze_capture.py` decodes it |
| `trainer_probe.py passive\|gears` | trainer handshake / gear stepping |
| `zwift_proto.py` | protobuf helpers + command builders + gear table |
| `bridge.py` | **working end-to-end reference**: Clicks → gears → trainer |
| `trainer_core.py` | shared BLE layer (trainer + Clicks, reconnects, button de-dup, cadence estimate) + local web server |
| `dashboard.py` + `.html` | guided test bench (port 8765) |
| `training.py` + `.html` | temporary training dashboard (port 8766): free ride, ERG, FTP workouts, laps; rides saved to `rides/` |

## 5. Verification status
- ✅ Virtual gears change resistance.
- ✅ Cadence: not sent by the trainer; the speed-based estimate works.
- ✅ SIM uphill grade, ✅ ERG (cadence-independent), ✅ ERG → SIM switch. ⚠️ Negative grade is ignored.
- ✅ Every Click button (both shifts, D-pad, A/B/Y/Z) detected with the owner filter.
- ⚠️ Long session: whole test run ≈ 12 min with 0 Click drops, but a 30+ min ride is still untested.

`dashboard.py` + `dashboard.html` is the guided test bench (live metrics, step instructions, auto-grading, CSV logging).
