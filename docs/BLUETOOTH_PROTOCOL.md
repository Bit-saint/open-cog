# Van Rysel D100 (Zwift Cog edition) + Zwift Click v2: Bluetooth LE protocol reference

A technical description of how an app talks to the **Van Rysel D100 direct-drive trainer** and the **Zwift Click v2**
controllers over Bluetooth Low Energy. It covers virtual shifting, SIM (grade) mode, ERG mode, live riding data and
controller button input. It is meant as the specification for a custom iOS app.

All of this was reverse-engineered on 2026-10-10 by talking to the real devices from a Windows PC (Python + `bleak`).
Every example packet in this document is either a captured packet or was produced by the encoder in `zwift_proto.py`
and accepted by the device.

**Legend**
- ✅ **Verified**: observed on these exact devices, including ride tests with a rider pedaling.
- 📚 **From source code**: taken from the open-source SHIFTR project (github.com/doudar/SHIFTR, `DirConManager.cpp`), which
  reverse-engineered the trainer side of the Zwift protocol. It's consistent with what was observed here but not independently proven.
- ❓ **Unknown / unverified**.

**Device versions tested**

| Device | Model / serial | Hardware | Firmware |
|---|---|---|---|
| Van Rysel D100 trainer | Decathlon model `355194`, name `VANRYSEL-HT-cc5a` | `1` | `0.108` (built `Jan 7 2025`) |
| Zwift Click v2, right | serial `0A-34C4590E1FA1` | `B.0` | `1.1.0` |
| Zwift Click v2, left | serial `0B-34C4590C8989` | `B.0` | `1.1.0` |

Behavior may change with other firmware versions.

---

## Contents

1. [System architecture](#1-system-architecture)
2. [Encoding primer: framing, protobuf, varints, zigzag](#2-encoding-primer)
3. [The shared Zwift GATT service](#3-the-shared-zwift-gatt-service)
4. [Zwift Click v2 (controllers)](#4-zwift-click-v2-controllers)
5. [Van Rysel D100 (trainer)](#5-van-rysel-d100-trainer)
6. [Derived values the app must compute](#6-derived-values-the-app-must-compute)
7. [App implementation guide (iOS / CoreBluetooth)](#7-app-implementation-guide-ios--corebluetooth)
8. [Gotchas and troubleshooting](#8-gotchas-and-troubleshooting)
9. [Verification status and open questions](#9-verification-status-and-open-questions)

---

## 1. System architecture

```
 ┌───────────────────┐   button bitmaps (notify)                     
 │ Zwift Click v2  L │ ───────────────────────┐                      
 │   (type 0x0B)     │                        │                      
 └─────────▲─────────┘                        ▼                      
           │ relays R presses      ┌─────────────────────┐   HubCommand (write)  ┌──────────────────┐
           │ (proprietary link)    │       YOUR APP      │ ────────────────────► │ Van Rysel D100   │
 ┌─────────┴─────────┐             │  • holds gear 1–24  │   gear ratio / grade  │  (simulates the  │
 │ Zwift Click v2  R │ ──────────► │  • grade / ERG      │   / ERG watts         │   chosen gear)   │
 │   (type 0x0A)     │  bitmaps    │  • physics, UI      │ ◄──────────────────── │                  │
 └───────────────────┘             └─────────────────────┘   RidingData (notify) └──────────────────┘
                                                               power, flywheel speed
```

Key points:

- **The controllers never talk to the trainer.** The app is the "gearbox". It keeps the current virtual gear and, on
  every shift, sends the new **gear ratio** to the trainer. The trainer then applies resistance as if that
  chainring/cog combination were fitted to the bike.
- The **Zwift Cog** is a single fixed rear cog, so the physical drivetrain ratio never changes. This makes virtual
  shifting possible, and it also means cadence can be derived from flywheel speed (§6.1).
- The app is a **BLE central** with three simultaneous connections: trainer, left Click and right Click. All three
  devices are peripherals.
- All three devices use the **same Zwift message framing** on the same three characteristic UUIDs (§3). Only the
  messages differ.
- **No encryption and no pairing/bonding** is required for any device. (The older Zwift Play controllers use ECDH and AES
  encryption; the Click v2 does not.) ✅

---

## 2. Encoding primer

### 2.1 Message framing ✅

Every message on the Zwift characteristics, in both directions, is:

```
┌──────────┬───────────────────────────────────────────┐
│ opcode   │ payload                                   │
│ 1 byte   │ protobuf wire-format message (0..N bytes) │
└──────────┴───────────────────────────────────────────┘
```

The one exception is the handshake, which is the raw ASCII string `RideOn` (§3.2).
There is no length prefix, checksum or sequence number. One BLE write or notification carries exactly one message, and
all messages seen were well under the negotiated MTU (Click 251 bytes, trainer 527 bytes on Windows).

### 2.2 Protobuf wire format (only what's needed)

There are no `.proto` files. The schema below was inferred, but decoding generic protobuf is easy to do by hand:

A message is a sequence of **fields**. Each field starts with a **key** varint:

```
key = (field_number << 3) | wire_type
```

| wire_type | meaning | value encoding | used here |
|---|---|---|---|
| 0 | VARINT | LEB128 varint | almost everything |
| 2 | LEN | varint length + bytes (nested message or bytes) | nested messages |
| 1 / 5 | 64 / 32-bit fixed | little-endian | not seen |

So the common key bytes are:

| key byte | field / type |
|---|---|
| `08` | field 1, varint |
| `10` | field 2, varint |
| `18` | field 3, varint |
| `20` | field 4, varint |
| `28` | field 5, varint |
| `12` | field 2, length-delimited |
| `22` | field 4, length-delimited |
| `2A` | field 5, length-delimited |

Note that the "sub-type" byte after an opcode (e.g. `04 22 …`, `04 2A …`) is simply the protobuf key of the first field.

### 2.3 Varint (unsigned LEB128)

Groups of 7 bits, least significant group first. The MSB of each byte means "more bytes follow".

```
150      = 0b1001_0110          → 96 01
24000    = 0x5DC0               → C0 BB 01
0xFFFFFFFF                      → FF FF FF FF 0F
```

```swift
func varint(_ v: UInt64) -> [UInt8] {
    var v = v, out: [UInt8] = []
    repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
    return out
}
func readVarint(_ d: [UInt8], _ i: inout Int) -> UInt64 {
    var v: UInt64 = 0, shift: UInt64 = 0
    while i < d.count { let b = d[i]; i += 1; v |= UInt64(b & 0x7F) << shift; if b & 0x80 == 0 { break }; shift += 7 }
    return v
}
```

### 2.4 Zigzag (signed values) 📚✅

Signed values (grade, wind) use protobuf `sint32` zigzag encoding, so bit 0 is the sign:

```
zigzag(n) = (n << 1) ^ (n >> 31)        // encode
n = (z >> 1) ^ -(z & 1)                 // decode

 0 → 0     1 → 2     -1 → 1     250 → 500     -250 → 499
```

### 2.5 Proto3 defaults

Zwift omits fields whose value is zero (the proto3 default). Receivers must treat a missing field as 0. The trainer
accepts both forms: an explicit zero (`10 00`) was accepted and behaved as 0 %. ✅

---

## 3. The shared Zwift GATT service

### 3.1 Characteristics ✅

Base UUID: `xxxxxxxx-19CA-4651-86E5-FA29DCDD09D1`

| UUID | Name used here | Properties | Direction | Purpose |
|---|---|---|---|---|
| `00000002-19CA-4651-86E5-FA29DCDD09D1` | **Async** | notify | device → app | unsolicited events: buttons, battery, riding data |
| `00000003-19CA-4651-86E5-FA29DCDD09D1` | **Sync RX** | write without response | app → device | commands and the handshake |
| `00000004-19CA-4651-86E5-FA29DCDD09D1` | **Sync TX** | indicate (Click: also read) | device → app | responses to commands (handshake reply) |

The containing **service UUID differs** between the two device types:

| Device | Service UUID |
|---|---|
| Trainer | `00000001-19CA-4651-86E5-FA29DCDD09D1` |
| Click v2 | `0000FC82-0000-1000-8000-00805F9B34FB` (16-bit `0xFC82`) |

### 3.2 Handshake ("RideOn") ✅

Identical for both device types:

```
App                                      Device
 │  enable notifications on 0x0002 (write CCCD 01 00)
 │  enable indications   on 0x0004 (write CCCD 02 00)
 │ ── write 0x0003 (no response): 52 69 64 65 4F 6E  ("RideOn") ──►│
 │ ◄── indicate 0x0004: "RideOn" [+ 2 bytes] ──────────────────────│
 │ ◄── notify 0x0002: device-specific stream begins ───────────────│
```

| Device | Reply on Sync TX (`0x0004`) | What follows on Async (`0x0002`) |
|---|---|---|
| Click v2 | `52 69 64 65 4F 6E` (`RideOn`) | `0x2A` info, `0xFF` logs, then `0x23` button states and `0x19` battery |
| Trainer | `52 69 64 65 4F 6E 02 00` (`RideOn` + `02 00`) | `0x03` RidingData at 1 Hz |

The two trailing bytes in the trainer reply are probably a protocol version ❓.
Without the handshake, the devices send no events. **Repeat the handshake after every reconnect.**

### 3.3 Opcode summary

| Opcode | Device | Direction | Meaning | Section |
|---|---|---|---|---|
| `0x52` (`'R'`) | both | both | `RideOn` handshake | 3.2 |
| `0x23` | Click | → app | button state bitmap | 4.4 |
| `0x19` | Click | → app | battery level | 4.5 |
| `0x2A` | Click | → app | device info / config after handshake | 4.6 |
| `0xFF` | Click | → app | diagnostic / log blobs | 4.6 |
| `0x03` | Trainer | → app | RidingData (power, speed) | 5.3 |
| `0x04` | Trainer | app → | HubCommand (ERG / SIM / gear) | 5.4 |
| `0x00`, `0x41` | Trainer | app → | status / info requests sent by Zwift; semantics unknown 📚❓ | 5.6 |

---

## 4. Zwift Click v2 (controllers)

A Click v2 set is **two separate BLE peripherals**, a left half and a right half. Each has its own buttons, battery and
connection.

### 4.1 Advertising and identification ✅

| Field | Right half | Left half |
|---|---|---|
| Local name | `Zwift Click` | `Zwift Click` |
| Service UUIDs | `0xFC82` | `0xFC82` |
| Manufacturer data, company `0x094A` (Zwift Inc) | `0A 1F A1` | `0B 89 89` |
| Service data `0xFC82` | `00` | `02` (❓ meaning; the value differed between halves) |

Manufacturer data layout (after the 2-byte little-endian company ID `4A 09`):

```
byte 0     device type   0x0A = Click v2 right, 0x0B = Click v2 left   (also the prefix of the serial "0A-…"/"0B-…")
byte 1..2  last two bytes of the device MAC address
```

On iOS, `CBAdvertisementDataManufacturerDataKey` gives the raw bytes including the company ID:
`4A 09 0A 1F A1`. **iOS hides MAC addresses**, so identify the halves by byte 2 (`0x0A`/`0x0B`) and remember
`peripheral.identifier` for reconnects.

**Sleep/wake**: a Click stops advertising after roughly a minute without a connection. Pressing any button wakes it.
While connected, it stays awake (tested for about 12 minutes).

### 4.2 GATT table ✅

```
Service 0x1800 Generic Access
  0x2A00 Device Name                 read,write   "Zwift Click"
  0x2A01 Appearance                  read,write   00 00
  0x2A04 Preferred Conn. Parameters  read         50 00 A0 00 00 00 E8 03
                                                   → interval 100–200 ms, latency 0, supervision timeout 10 s
  0x2AA6 Central Address Resolution  read         01
  0x2AC9 RPA Only                    read         00
Service 0x1801 Generic Attribute
  0x2A05 Service Changed             indicate
Service 0x180A Device Information
  0x2A29 Manufacturer                read         "Zwift Inc"
  0x2A25 Serial Number               read         "0A-34C4590E1FA1" / "0B-34C4590C8989"
  0x2A27 Hardware Revision           read         "B.0"
  0x2A26 Firmware Revision           read         "1.1.0"
Service 0xFC82 Zwift
  00000002-19CA-…  Async             notify
  00000003-19CA-…  Sync RX           write-without-response
  00000004-19CA-…  Sync TX           read, indicate
  00000100-19CA-…  ❓                write, write-without-response, notify   (+ user description descriptor)
  00000101-19CA-…  ❓                write, write-without-response, notify   (+ user description descriptor)
  00000102-19CA-…  ❓                write-without-response, notify          (+ user description descriptor)
Service 0x180F Battery
  0x2A19 Battery Level               read, notify  0x64 = 100 %
```

`0x0100`–`0x0102` are not needed for button input. They may be firmware update or debug channels. Don't write to them.

### 4.3 Connection sequence ✅

1. Connect.
2. Discover service `0xFC82`.
3. Enable notifications on `…0002` and indications on `…0004`.
4. Write `RideOn` to `…0003` (write without response).
5. Receive the `RideOn` indication. Button events then start arriving on `…0002`.

### 4.4 Button state, opcode `0x23` ✅

```
23 08 <varint bitmap>
│  │
│  └ protobuf field 1 (varint) = 32-bit button bitmap
└ opcode
```

**Bits are active-low: a bit that is 0 means the button is pressed.**
The idle state is all ones: `23 08 FF FF FF FF 0F` → bitmap `0xFFFFFFFF`.

**Button map** (this is the Zwift Ride keymap; the Click v2 implements a subset):

| Bit | Mask | Zwift name | Click v2 button | Physically on | Suggested use |
|---|---|---|---|---|---|
| 0 | `0x00000001` | LEFT | D-pad left | left (0x0B) | |
| 1 | `0x00000002` | UP | D-pad up | left | grade + / menu up |
| 2 | `0x00000004` | RIGHT | D-pad right | left | skip interval |
| 3 | `0x00000008` | DOWN | D-pad down | left | grade − / menu down |
| 4 | `0x00000010` | A | A | right (0x0A) | |
| 5 | `0x00000020` | B | B | right | |
| 6 | `0x00000040` | Y | Y | right | |
| 7 | `0x00000080` | Z | Z | right | |
| 8 | `0x00000100` | SHIFT_UP_L | **left shift paddle** | left | **gear − (easier)** |
| 9 | `0x00000200` | SHIFT_DN_L | not present | | |
| 10 | `0x00000400` | POWERUP_L | not present | | |
| 11 | `0x00000800` | ONOFF_L | not present | | |
| 12 | `0x00001000` | SHIFT_UP_R | **right shift paddle** | right | **gear + (harder)** |
| 13 | `0x00002000` | SHIFT_DN_R | not present | | |
| 14 | `0x00004000` | POWERUP_R | not present | | |
| 15 | `0x00008000` | ONOFF_R | not present | | |

Every button marked as present was individually confirmed in the ride test (both shifts ×3, all four D-pad
directions, and A/B/Y/Z). ✅

**Worked examples**

| Packet | Bitmap | Pressed |
|---|---|---|
| `23 08 FF FF FF FF 0F` | `0xFFFFFFFF` | none |
| `23 08 FF DF FF FF 0F` | `0xFFFFEFFF` | bit 12 → right shift |
| `23 08 FF FD FF FF 0F` | `0xFFFFFEFF` | bit 8 → left shift |
| `23 08 EF FF FF FF 0F` | `0xFFFFFFEF` | bit 4 → A |
| `23 08 FE FF FF FF 0F` | `0xFFFFFFFE` | bit 0 → D-pad left |

**Timing** ✅
- While any button is held, the frame repeats about every **90 ms**, so you can implement hold-to-repeat.
- The right half was seen streaming idle frames continuously at about 90 ms. The left half sent frames only around
  state changes. **Don't rely on the frame rate**; act on state *changes*.
- Measured hold: one 3.4 s press produced a continuous run of "pressed" frames followed by one "released" frame.

**Edge detection** (what the app should do):

```swift
let pressedNow  = ~bitmap        & 0xFFFF       // 1 = pressed (active-low inverted)
let pressedPrev = ~prevBitmap    & 0xFFFF
let newPresses  = pressedNow & ~pressedPrev     // rising edges → act on these
prevBitmap = bitmap
```

#### 4.4.1 Relay between halves ⚠️ ✅

**The left half (`0x0B`) also reports the right half's presses.** The two halves are linked, and the left one relays.
With both halves connected, one right-shift press arrives twice, once from each half, which causes double shifts.
This was observed and fixed during testing.

Rule: **accept each bit only from the half that physically owns it** (column "Physically on" above). If the owner half
is not connected, accept the relayed copy, so a single connection to the left half can serve both halves.

```swift
let owner: [Int: ClickSide] = [0:.left, 1:.left, 2:.left, 3:.left, 8:.left, 9:.left, 10:.left, 11:.left,
                               4:.right, 5:.right, 6:.right, 7:.right, 12:.right, 13:.right, 14:.right, 15:.right]
for bit in newPressBits(from: side) {
    if let o = owner[bit], o != side, connected.contains(o) { continue }   // relayed duplicate
    handle(bit)
}
```

With this filter, 5 presses per side moved the gear exactly 12 → 17 → 12 ✅.
Whether the right half also relays the left half's presses was not observed.

### 4.5 Battery, opcode `0x19` ✅

```
19 10 64      → field 2 = 100 (%)
```

Sent about every **5 s**. The standard Battery Service (`0x180F` / `0x2A19`, read and notify) carries the same value
and was seen notifying at the same moments.

### 4.6 Device info `0x2A` and diagnostics `0xFF` ✅ (content ❓)

Sent by the left half right after the handshake. Both can be ignored.

```
2A 08 03 12 13 12 11 08 30 10 00 18 C0 07 22 05 CF FF FF FF 1F 28 FB 01
   → 1:3  2:{ 2:{ 1:48  2:0  3:960  4:<CF FF FF FF 1F>  5:251 } }
```
The field meanings are unknown. Field 4 contains a varint (`0x1FFFFFFCF`) that looks like a button mask.

```
FF 05 00 FA 05 18 0A 0C "34C4590C8989" 20 64 28 64 30 81 17 38 81 17
FF 03 00 0A 21 03 4A … (≈90 bytes, high entropy)
```
`0xFF` messages are logs or diagnostics. They have a 5-byte header, embed the device serial, and some look
encrypted or compressed.

---

## 5. Van Rysel D100 (trainer)

### 5.1 Advertising and identification ✅

- Local name `VANRYSEL-HT-xxxx` (last four hex digits of the address; here `VANRYSEL-HT-cc5a`).
- During Windows scanning no service UUIDs appeared in the advertisement, so **identify the trainer by name prefix**,
  or by the FTMS / Zwift services after connecting.
- MTU negotiated on Windows: 527.

### 5.2 GATT table ✅

```
Service 0x1800 Generic Access            Device Name "VANRYSEL-HT-cc5a", Appearance 00 00
Service 0x1801 Generic Attribute         Service Changed, Client Supported Features, Database Hash
Service 0x180A Device Information
  Manufacturer "DECATHLON" · Model "355194" · Serial "255000374" · HW "1" · FW "0.108"
  SW "Jan  7 2025 - 10:09:19" · System ID 12 34 56 FF FE 9A BC DE · PnP ID 02 5E 04 40 00 00 03
Service F000FFC0-0451-4000-B000-000000000000   ⛔ TI OAD (firmware update), never write
  F000FFC1-…  notify, write, write-without-response
  F000FFC2-…  notify, write, write-without-response
Service 8CE5CC01-0A4D-11E9-AB14-D663BD873D93   ❓ vendor (Decathlon?), leave alone
  8CE5CC02-…  notify, write, write-without-response
  8CE5CC03-…  notify, write, write-without-response
Service 8CE5EE01-0A4D-11E9-AB14-D663BD873D93   ❓ vendor, leave alone
  8CE5EE02-…  notify, write, write-without-response
Service 0x1826 Fitness Machine (FTMS)
  0x2ACC Feature                         read     01 40 00 00 0C A0 00 00
  0x2AD2 Indoor Bike Data                notify
  0x2AD5 Supported Inclination Range     read     00 00 3C 00 01 00   → 0.0 … 6.0 %, step 0.1
  0x2AD6 Supported Resistance Range      read     00 00 64 00 01 00   → raw 0 … 100, step 1 (FTMS unit 0.1 → 0.0 … 10.0)
  0x2AD8 Supported Power Range           read     32 00 58 02 01 00   → 50 … 600 W, step 1
  0x2AD9 Control Point                   write, write-without-response, indicate
  0x2ADA Machine Status                  notify
Service 0x1818 Cycling Power
  0x2A63 Measurement                     notify
  0x2A65 Feature                         read     FF 1F 00 00
  0x2A5D Sensor Location                 read     0C (rear wheel)
Service 00000001-19CA-4651-86E5-FA29DCDD09D1   Zwift (virtual shifting)
  00000002-…  Async     notify
  00000003-…  Sync RX   write-without-response
  00000004-…  Sync TX   indicate
```

The **Zwift service is the main interface.** FTMS and Cycling Power are a standard alternative (§5.7–5.8).

### 5.3 RidingData, opcode `0x03` (Async, 1 Hz) ✅

Sent once per second after the handshake, even at rest.

```
03 08 22 10 00 18 E8 03 20 22 28 91 6D
   → 1:34  2:0  3:488  4:34  5:13969
```

| Field | Type | Meaning | Evidence |
|---|---|---|---|
| 1 | varint | **power, W** | matches FTMS power at the same moments |
| 2 | varint | cadence, rpm. **Always 0 on the D100**, even while pedaling | 12+ min of riding |
| 3 | varint | **flywheel speed, m/s × 100** (488 = 4.88 m/s = 17.6 km/h). This is *physical* speed, not virtual | matches FTMS speed (17.5 km/h) |
| 4 | varint | power, W (identical to field 1 in every frame captured) | |
| 5 | varint | ❓ always ≈ 28.6 × field 3; probably another speed unit (flywheel rpm × k?) | |

At rest: `03 08 00 10 00 18 00 20 00 28 00` (all fields explicitly 0).

> Note: the commonly circulated "Zwift Hub" description (field 3 = speed in km/h × 100, field 4 = heart rate) does **not**
> match the D100. Use the table above.

### 5.4 HubCommand, opcode `0x04` (Sync RX)

All control goes through one message type: opcode `0x04` followed by a protobuf with one of three fields.
Writes use **write without response**. **The trainer sends no acknowledgement** for any command; the only way to
confirm a command is the change in power or speed. ✅

```
HubCommand {
  3: uint32      erg_watts           → ERG mode
  4: Simulation  simulation          → SIM mode, road parameters
  5: Physical    physical            → virtual gear + masses
}
Simulation {                          Physical {
  1: sint32 wind     (m/s × 100)        2: uint32 gear_ratio  (× 10000)
  2: sint32 grade    (% × 100)          4: uint32 bike_mass   (kg × 100)
  3: uint32 cwa      (× 10000)          5: uint32 rider_mass  (kg × 100)
  4: uint32 crr      (× 100000)       }
}
```
Field numbers are 📚 (SHIFTR) and ✅ (accepted by the D100 with the expected effect). The scale factors for
wind / CwA / Crr are 📚. Grade, gear and ERG scales are ✅.

#### 5.4.1 Set virtual gear (Physical, field 5) ✅

```
04 2A <len> 10 <ratio×10000> 20 <bike kg×100> 28 <rider kg×100>
```

| Example | Bytes |
|---|---|
| gear 12 (2.40), bike 10 kg, rider 75 kg | `04 2A 0A 10 C0 BB 01 20 E8 07 28 CC 3A` |
| gear 1 (0.75), 10 kg, 75 kg | `04 2A 09 10 CC 3A 20 E8 07 28 CC 3A` |
| gear 24 (5.49), 10 kg, 75 kg | `04 2A 0A 10 F4 AC 03 20 E8 07 28 CC 3A` |
| gear 12, bike 9 kg, rider 80 kg | `04 2A 0A 10 C0 BB 01 20 84 07 28 C0 3E` |

- **Gear ratio** = chainring ÷ cog of the *virtual* drivetrain, × 10000.
- A ratio of 0 switches virtual shifting off (plain SIM). 📚❓
- **Masses** affect how hard a grade feels. Send the real rider weight.
- The command takes effect in **about 1–2 s** ✅.

**Zwift's 24-gear table** (gear → ratio → varint bytes):

| Gear | Ratio | Varint | Gear | Ratio | Varint | Gear | Ratio | Varint |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.75 | `CC 3A` | 9 | 1.86 | `A8 91 01` | 17 | 3.49 | `D4 90 02` |
| 2 | 0.87 | `FC 43` | 10 | 2.04 | `B0 9F 01` | 18 | 3.74 | `98 A4 02` |
| 3 | 0.99 | `AC 4D` | 11 | 2.22 | `B8 AD 01` | 19 | 3.99 | `DC B7 02` |
| 4 | 1.11 | `DC 56` | 12 | 2.40 | `C0 BB 01` | 20 | 4.24 | `A0 CB 02` |
| 5 | 1.23 | `8C 60` | 13 | 2.61 | `F4 CB 01` | 21 | 4.54 | `D8 E2 02` |
| 6 | 1.38 | `E8 6B` | 14 | 2.82 | `A8 DC 01` | 22 | 4.84 | `90 FA 02` |
| 7 | 1.53 | `C4 77` | 15 | 3.03 | `DC EC 01` | 23 | 5.14 | `C8 91 03` |
| 8 | 1.68 | `A0 83 01` | 16 | 3.24 | `90 FD 01` | 24 | 5.49 | `F4 AC 03` |

Gear 12 (2.40 ≈ 34×14) is a sensible starting gear. The table is Zwift's; any ratio can be sent.

**Measured effect** ✅ (flat road, steady effort, 15 s per gear):

| Gear | 4 | 8 | 12 | 16 | 20 |
|---|---|---|---|---|---|
| Power | 42 W | 38–48 W | 79–90 W | 149 W | 245 W |

Below about gear 8 the trainer reaches a **minimum resistance floor** (~40 W at ~25 km/h flywheel speed).

#### 5.4.2 Set road conditions (Simulation, field 4) ✅

```
04 22 <len> [08 <zigzag wind>] 10 <zigzag grade×100> 18 <cwa×10000> 20 <crr×100000>
```

Zwift-standard values (📚): **CwA = 5100 (0.51)**, **Crr = 400 (0.004)**. Wind is omitted when 0.

| Example | Bytes |
|---|---|
| flat 0 % | `04 22 08 10 00 18 EC 27 20 90 03` |
| +2.5 % | `04 22 09 10 F4 03 18 EC 27 20 90 03` |
| −2.5 % | `04 22 09 10 F3 03 18 EC 27 20 90 03` |
| +4 % | `04 22 09 10 A0 06 18 EC 27 20 90 03` |
| +3 %, wind 5 m/s | `04 22 0C 08 E8 07 10 D8 04 18 EC 27 20 90 03` |

**Measured effect** ✅ (gear 8, ~80 rpm, rider 75 kg):

| Grade | −2 % | 0 % | +2 % | +4 % |
|---|---|---|---|---|
| Power | 63 W | 54–60 W | 101 W | 164 W |

- Uphill scales roughly linearly ✅.
- **Negative grades have no effect** ⚠️. −2 % feels like flat, and FTMS also reports an inclination range of 0…6 %. The
  app must simulate descents itself (e.g. treat them as flat and show a higher virtual speed).
- Grade and gear combine. The trainer computes resistance from grade, masses, CwA/Crr, the virtual gear and flywheel speed.
- Sending Simulation, or Physical, **leaves ERG mode** ✅.

#### 5.4.3 ERG mode (field 3) ✅

```
04 18 <watts varint>
```

| Example | Bytes |
|---|---|
| 100 W | `04 18 64` |
| 150 W | `04 18 96 01` |
| 250 W | `04 18 FA 01` |

**Measured effect** ✅:

| Target | 100 W @80 | 150 W @81 | 150 W @66 | 150 W @91 | 100 W @80 |
|---|---|---|---|---|---|
| Average (±sd) | 100 (±0) | 150 (±1) | 150 (±1) | 152 (±7) | 100 (±0) |

- ERG holds the target independently of cadence (66–91 rpm tested).
- Exit ERG by sending Simulation (`04 22 …`) plus Physical (`04 2A …`) again ✅.
- FTMS advertises a 50–600 W power range. Expect the same limits.
- During ERG the reported power is unusually smooth (±0–1 W). The trainer may smooth or report near-target values. ❓

#### 5.4.4 Command timing

- Zwift sends Simulation roughly once per second while riding 📚. The dashboards here resend the current state
  **every 2 s**, plus immediately on change, and that worked reliably ✅.
- Send Physical only when the gear (or a mass) changes. Resend it after leaving ERG and after a reconnect.
- There is no flow control. Use `canSendWriteWithoutResponse` / `peripheralIsReady(toSendWriteWithoutResponse:)` on iOS.

### 5.5 Mode state machine

```
                 04 18 <W>                 
     ┌──────────────────────────────┐      
     │                              ▼      
 ┌───────┐   04 22 / 04 2A    ┌─────────┐  
 │  SIM  │ ◄───────────────── │   ERG   │  
 │ +gear │                    │  hold W │  
 └───────┘                    └─────────┘  
   ▲  04 2A (ratio) changes resistance
   └─ 04 22 (grade) changes resistance
```

Before the first command after a handshake, the trainer behaves like a basic resistance unit (the "RidingData at
rest" state). The dashboards always send Simulation + Physical immediately after the handshake.

### 5.6 Other Zwift opcodes 📚❓

The SHIFTR source shows Zwift also sending `0x00 …` (a status/info request) and `0x41 …` (unknown) on Sync RX, and a
trainer-side async reply `2A 08 03 12 0D 22 0B "RIDE_ON(0)" …`. None of these are needed for control, and the D100's
answers to them were not explored.

### 5.7 FTMS (Fitness Machine Service), the standard alternative

- **Feature** `01 40 00 00 0C A0 00 00`
  - Machine features `0x00004001`: average speed (bit 0), power measurement (bit 14). **No cadence bit.**
  - Target settings `0x0000A00C`: resistance (bit 2), power (bit 3), **indoor bike simulation** (bit 13), spin-down (bit 15).
- **Indoor Bike Data** (~4 Hz): only speed + power flags were ever set ✅, so there is no cadence here either.
- **Control Point** (`0x2AD9`) follows the standard FTMS spec: `00` request control, `05 <sint16 W>` target power,
  `11 <wind sint16, 0.001 m/s> <grade sint16, 0.01 %> <crr u8, 0.0001> <cw u8, 0.01 kg/m>` simulation parameters. **Not exercised in testing** ❓.
- FTMS has no notion of virtual gears. To shift with FTMS only, the app would have to fake gears by scaling the grade or
  power. The Zwift service is the better path on this trainer.
- Don't mix FTMS control and Zwift control in the same session. ❓

### 5.8 Cycling Power Service

- Feature `FF 1F 00 00` claims crank revolution data, **but every measurement had flags `0x0001`** (pedal power balance
  only): no wheel or crank revolution data ✅. It's usable as a second power source but not for cadence.

---

## 6. Derived values the app must compute

### 6.1 Cadence ✅

The D100 sends **no cadence anywhere**: Zwift field 2 is 0, FTMS has no cadence flag, and Cycling Power has no crank
data. Because the Zwift Cog fixes the physical gear, cadence is directly proportional to flywheel speed:

```
cadence_rpm = flywheel_mps / (chainring_teeth / cog_teeth × wheel_circumference_m) × 60

flywheel_mps        = RidingData field 3 / 100
cog_teeth           = 14            (Zwift Cog)
wheel_circumference = 2.096 m       (700×25c; assumed to be what the trainer uses)
chainring_teeth     = user setting  (34 in testing)
```

Validation with a 34T chainring ✅: the rider targeted 60 / 80 / 100 rpm by feel and the estimate read 60 / 80 / 96.
Example: 26.1 km/h → 7.25 m/s ÷ (34/14 × 2.096) × 60 ≈ 85 rpm. Make the chainring user-configurable, and consider a
one-time calibration against a real cadence sensor.

### 6.2 Virtual speed and distance

The flywheel speed is physical, so the in-game speed must be computed from power with road physics
(the same constants as the Simulation command):

```
P = v · m·g·(sin θ + Crr·cos θ) + CwA · v³          θ = atan(grade/100), m = rider + bike, Crr = 0.004, CwA = 0.51
```

Solve for `v` numerically (bisection over 0…30 m/s works). Integrate `v` for distance. Use the *requested* grade
(including negative grades the trainer ignores) so descents still feel fast on screen.

### 6.3 Ride metrics (standard)

- **Normalized Power**: 4th root of the mean of (30 s rolling average power)⁴.
- **TSS** = seconds × NP² / (FTP² × 3600) × 100.
- **Ramp-test FTP estimate** = 0.75 × best 1-minute power.
- **Auto-pause**: no power and flywheel < 0.5 m/s for more than 3 s.

---

## 7. App implementation guide (iOS / CoreBluetooth)

### 7.1 Setup
- `Info.plist`: `NSBluetoothAlwaysUsageDescription`. For riding with the screen locked, add the background mode
  `bluetooth-central`. Use state restoration (`CBCentralManagerOptionRestoreIdentifierKey`) to survive app suspension.

### 7.2 Discovery
```swift
central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
    if let m = ad[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 3, m[0] == 0x4A, m[1] == 0x09 {
        switch m[2] { case 0x0A: found(.clickRight, p); case 0x0B: found(.clickLeft, p); default: break }
    } else if let name = ad[CBAdvertisementDataLocalNameKey] as? String ?? p.name, name.hasPrefix("VANRYSEL") {
        found(.trainer, p)
    }
}
```
Scanning with a service filter of `[CBUUID(string: "FC82")]` also finds the Clicks. Save each `p.identifier` and use
`retrievePeripherals(withIdentifiers:)` next time.

### 7.3 Per-device bring-up
```swift
let zAsync = CBUUID(string: "00000002-19CA-4651-86E5-FA29DCDD09D1")
let zRx    = CBUUID(string: "00000003-19CA-4651-86E5-FA29DCDD09D1")
let zTx    = CBUUID(string: "00000004-19CA-4651-86E5-FA29DCDD09D1")
// trainer service: 00000001-19CA-4651-86E5-FA29DCDD09D1, click service: FC82
// after didDiscoverCharacteristics:
p.setNotifyValue(true, for: asyncChar)     // CoreBluetooth picks notify vs indicate automatically
p.setNotifyValue(true, for: txChar)
// after both didUpdateNotificationStateFor callbacks:
p.writeValue(Data("RideOn".utf8), for: rxChar, type: .withoutResponse)
```

### 7.4 Building trainer commands
```swift
func field(_ n: UInt64, _ v: UInt64) -> [UInt8] { varint(n << 3) + varint(v) }
func message(_ n: UInt64, _ body: [UInt8]) -> [UInt8] { varint(n << 3 | 2) + varint(UInt64(body.count)) + body }
func zigzag(_ v: Int64) -> UInt64 { UInt64(bitPattern: (v << 1) ^ (v >> 63)) }

func ergCommand(watts: Int) -> Data { Data([0x04] + field(3, UInt64(watts))) }

func simCommand(gradePercent: Double, windMps: Double = 0, cwa: Double = 0.51, crr: Double = 0.004) -> Data {
    var b: [UInt8] = []
    if windMps != 0 { b += field(1, zigzag(Int64((windMps * 100).rounded()))) }
    b += field(2, zigzag(Int64((gradePercent * 100).rounded())))
    b += field(3, UInt64((cwa * 10000).rounded())) + field(4, UInt64((crr * 100000).rounded()))
    return Data([0x04] + message(4, b))
}

func gearCommand(ratio: Double, bikeKg: Double, riderKg: Double) -> Data {
    let b = field(2, UInt64((ratio * 10000).rounded())) + field(4, UInt64((bikeKg * 100).rounded()))
          + field(5, UInt64((riderKg * 100).rounded()))
    return Data([0x04] + message(5, b))
}
// gearCommand(ratio: 2.40, bikeKg: 10, riderKg: 75) == 04 2A 0A 10 C0 BB 01 20 E8 07 28 CC 3A
```

### 7.5 Parsing
```swift
// Generic: returns [fieldNumber: UInt64] for varint fields of a flat message
func varintFields(_ d: [UInt8], from start: Int = 1) -> [Int: UInt64] {
    var i = start, out: [Int: UInt64] = [:]
    while i < d.count {
        let key = readVarint(d, &i), num = Int(key >> 3), wt = key & 7
        if wt == 0 { out[num] = readVarint(d, &i) }
        else if wt == 2 { let len = Int(readVarint(d, &i)); i += len }   // skip nested
        else { break }
    }
    return out
}
// Trainer 0x03:   power = f[1], flywheel m/s = f[3] / 100
// Click   0x23:   bitmap = f[1]  (active-low)
// Click   0x19:   battery % = f[2]
```

### 7.6 Runtime loop
1. Keep app state: `gear` (1…24), `mode` (SIM/ERG), `grade`, `ergWatts`, masses.
2. On a Click press (edge, after the owner filter): update state, then send the matching command immediately.
3. Every 2 s: resend Simulation (SIM) or ERG (ERG mode).
4. On trainer reconnect: handshake, Simulation, Physical (or ERG).
5. On a Click disconnect: keep scanning or retrieving and reconnect. The Click sleeps when disconnected, so the user has
   to press a button to wake it.

---

## 8. Gotchas and troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Device not found while scanning | Click asleep, or another app (Zwift, phone) holds the connection | press a button; close other apps; one central per device |
| Connected but no events | handshake missing, or sent before notifications were enabled | enable CCCDs first, then write `RideOn`; redo after reconnect |
| One press shifts two gears | left half relays the right half's presses | owner filter (§4.4.1) |
| Cadence always 0 | the D100 doesn't send it | estimate from flywheel speed (§6.1) |
| Speed looks too low or constant across gears | field 3 is physical flywheel speed | compute virtual speed (§6.2) |
| Downhill feels like flat | trainer ignores grade < 0 | simulate descents in the app |
| Very low gears feel identical | minimum resistance floor (~40 W) | expected hardware behavior |
| Shift seems ignored | gear commands are ignored in ERG; or a 1–2 s response delay | leave ERG first; allow for the delay |
| After a script or app crash the devices won't reconnect for ~20 s | old link still alive until the supervision timeout | wait, or reconnect with retries |
| Windows console crash on `→` in logs | cp1252 console | reconfigure stdout to UTF-8 (done in `trainer_core.py`) |

**Never write to** the TI OAD service `F000FFC0-…` (firmware update) or the unknown `8CE5…` vendor services on the
trainer, or to `0x0100`–`0x0102` on the Clicks.

---

## 9. Verification status and open questions

| Item | Status |
|---|---|
| Handshake, both device types | ✅ |
| All Click v2 buttons + relay behavior | ✅ |
| Click battery (`0x19` and BAS) | ✅ |
| Click session stability | ✅ about 12 min with 0 drops; 30+ min not tested |
| Trainer RidingData fields 1, 3 (and 4 = duplicate power) | ✅ |
| Virtual gear (Physical) changes resistance | ✅ |
| SIM uphill grade | ✅ |
| SIM negative grade | ⚠️ no effect |
| ERG accuracy and cadence independence; ERG → SIM switch | ✅ |
| Cadence from flywheel speed | ✅ (34T, rider-felt targets) |
| RidingData field 5 meaning | ❓ |
| Click `0x2A` content, Click service-data byte, `0x0100`–`0x0102` | ❓ |
| Trainer reply bytes `02 00` after RideOn | ❓ (likely protocol version) |
| Wind / CwA / Crr effect on the D100 | ❓ (sent with Zwift defaults only) |
| Gear ratio 0 = virtual shifting off | 📚 not tested |
| FTMS Control Point on the D100 | ❓ not tested |
| Zwift opcodes `0x00` / `0x41` | 📚❓ |

### Reference code in this folder

| File | What it shows |
|---|---|
| `zwift_proto.py` | varint / zigzag / protobuf decode, command builders, gear table |
| `trainer_core.py` | complete working BLE layer: discovery, reconnects, handshake, Click owner filter, cadence estimate, command loop |
| `bridge.py` | minimal Clicks → gears → trainer example |
| `training.py` / `dashboard.py` | full apps built on the above (training dashboard / guided test bench) |
| `gatt_*.txt`, `capture_*.txt`, `results/`, `rides/` | raw dumps, captures and ride-test data behind the ✅ marks |

### Sources
- Device captures and ride tests in this folder (primary source).
- SHIFTR by doudar: https://github.com/doudar/SHIFTR (`src/DirConManager.cpp`, `VirtualShifting.md`): HubCommand field
  layout, gear table and Zwift CwA/Crr defaults.
