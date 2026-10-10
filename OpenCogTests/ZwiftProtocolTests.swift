import XCTest
@testable import OpenCog

/// Byte vectors are the captured / device-accepted packets from docs/BLUETOOTH_PROTOCOL.md.
final class ZwiftProtocolTests: XCTestCase {
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func bytes(_ string: String) -> Data {
        Data(string.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    // MARK: Primitives

    func testVarint() {
        XCTAssertEqual(Protobuf.varint(150), [0x96, 0x01])
        XCTAssertEqual(Protobuf.varint(24000), [0xC0, 0xBB, 0x01])
        XCTAssertEqual(Protobuf.varint(0xFFFF_FFFF), [0xFF, 0xFF, 0xFF, 0xFF, 0x0F])
        var index = 0
        XCTAssertEqual(Protobuf.readVarint([0xC0, 0xBB, 0x01], &index), 24000)
        XCTAssertEqual(index, 3)
    }

    func testZigzag() {
        XCTAssertEqual(Protobuf.zigzag(0), 0)
        XCTAssertEqual(Protobuf.zigzag(1), 2)
        XCTAssertEqual(Protobuf.zigzag(-1), 1)
        XCTAssertEqual(Protobuf.zigzag(250), 500)
        XCTAssertEqual(Protobuf.zigzag(-250), 499)
        XCTAssertEqual(Protobuf.unzigzag(499), -250)
    }

    // MARK: Trainer commands

    func testGearCommands() {
        XCTAssertEqual(hex(Zwift.physicalCommand(gearRatio: 2.40, bikeKg: 10, riderKg: 75)),
                       "04 2A 0A 10 C0 BB 01 20 E8 07 28 CC 3A")
        XCTAssertEqual(hex(Zwift.physicalCommand(gearRatio: 0.75, bikeKg: 10, riderKg: 75)),
                       "04 2A 09 10 CC 3A 20 E8 07 28 CC 3A")
        XCTAssertEqual(hex(Zwift.physicalCommand(gearRatio: 5.49, bikeKg: 10, riderKg: 75)),
                       "04 2A 0A 10 F4 AC 03 20 E8 07 28 CC 3A")
        XCTAssertEqual(hex(Zwift.physicalCommand(gearRatio: 2.40, bikeKg: 9, riderKg: 80)),
                       "04 2A 0A 10 C0 BB 01 20 84 07 28 C0 3E")
    }

    func testSimulationCommands() {
        XCTAssertEqual(hex(Zwift.simulationCommand(gradePercent: 0)), "04 22 08 10 00 18 EC 27 20 90 03")
        XCTAssertEqual(hex(Zwift.simulationCommand(gradePercent: 2.5)), "04 22 09 10 F4 03 18 EC 27 20 90 03")
        XCTAssertEqual(hex(Zwift.simulationCommand(gradePercent: -2.5)), "04 22 09 10 F3 03 18 EC 27 20 90 03")
        XCTAssertEqual(hex(Zwift.simulationCommand(gradePercent: 4)), "04 22 09 10 A0 06 18 EC 27 20 90 03")
        XCTAssertEqual(hex(Zwift.simulationCommand(gradePercent: 3, windMps: 5)),
                       "04 22 0C 08 E8 07 10 D8 04 18 EC 27 20 90 03")
    }

    func testErgCommands() {
        XCTAssertEqual(hex(Zwift.ergCommand(watts: 100)), "04 18 64")
        XCTAssertEqual(hex(Zwift.ergCommand(watts: 150)), "04 18 96 01")
        XCTAssertEqual(hex(Zwift.ergCommand(watts: 250)), "04 18 FA 01")
    }

    func testGearTable() {
        XCTAssertEqual(GearTable.ratios.count, 24)
        XCTAssertEqual(GearTable.ratio(forGear: 12), 2.40)
        XCTAssertEqual(GearTable.ratio(forGear: 0), 0.75)
        XCTAssertEqual(GearTable.ratio(forGear: 99), 5.49)
    }

    // MARK: Parsing

    func testRidingData() {
        let riding = RidingData(bytes("03 08 22 10 00 18 E8 03 20 22 28 91 6D"))
        XCTAssertEqual(riding, RidingData(power: 34, flywheelSpeed: 4.88))
        XCTAssertEqual(RidingData(bytes("03 08 00 10 00 18 00 20 00 28 00")), RidingData(power: 0, flywheelSpeed: 0))
        XCTAssertNil(RidingData(bytes("23 08 FF FF FF FF 0F")))
    }

    func testRideOnReply() {
        XCTAssertTrue(Zwift.isRideOnReply(bytes("52 69 64 65 4F 6E 02 00")))
        XCTAssertTrue(Zwift.isRideOnReply(bytes("52 69 64 65 4F 6E")))
        XCTAssertFalse(Zwift.isRideOnReply(bytes("52 69 64")))
    }

    func testClickMessages() {
        XCTAssertEqual(ClickMessage(bytes("23 08 FF FF FF FF 0F")), .buttons(0xFFFF_FFFF))
        XCTAssertEqual(ClickMessage(bytes("23 08 FF DF FF FF 0F")), .buttons(0xFFFF_EFFF))
        XCTAssertEqual(ClickMessage(bytes("19 10 64")), .battery(100))
        XCTAssertEqual(ClickMessage(bytes("2A 08 03")), .other(opcode: 0x2A))
    }

    func testIndoorBikeData() {
        // Speed + power only, as the D100 sends: flags 0x0040, 17.50 km/h, 34 W.
        let d100 = IndoorBikeData(Data([0x40, 0x00, 0xD6, 0x06, 0x22, 0x00]))
        XCTAssertEqual(d100, IndoorBikeData(speedKmh: 17.5, cadence: nil, power: 34))
        // Speed + cadence + power: 26.10 km/h, 85 rpm, 200 W.
        let full = IndoorBikeData(Data([0x44, 0x00, 0x32, 0x0A, 0xAA, 0x00, 0xC8, 0x00]))
        XCTAssertEqual(full, IndoorBikeData(speedKmh: 26.1, cadence: 85, power: 200))
        XCTAssertNil(IndoorBikeData(Data([0x40, 0x00, 0xD6])))
    }

    func testCyclingPowerMeasurement() {
        XCTAssertEqual(CyclingPowerMeasurement(Data([0x01, 0x00, 0x96, 0x00, 0x32]))?.power, 150)
        XCTAssertNil(CyclingPowerMeasurement(Data([0x01, 0x00, 0x96])))
    }

    func testHeartRateMeasurement() {
        XCTAssertEqual(HeartRateMeasurement(Data([0x00, 0x48]))?.bpm, 72)
        XCTAssertEqual(HeartRateMeasurement(Data([0x01, 0x2C, 0x01]))?.bpm, 300)
        XCTAssertEqual(HeartRateMeasurement(Data([0x06, 0x50]))?.sensorContact, true)
        XCTAssertNil(HeartRateMeasurement(Data([0x01, 0x2C])))
    }
}

final class ClickInputTests: XCTestCase {
    private let idle: UInt32 = 0xFFFF_FFFF
    private let rightShift: UInt32 = 0xFFFF_EFFF
    private let leftShift: UInt32 = 0xFFFF_FEFF

    func testEdgeDetection() {
        var input = ClickInputProcessor(holdToRepeat: false)
        let both: Set<ClickSide> = [.left, .right]
        XCTAssertEqual(input.process(bitmap: rightShift, from: .right, connected: both, now: 0), [.shiftRight])
        XCTAssertEqual(input.process(bitmap: rightShift, from: .right, connected: both, now: 0.09), [])
        XCTAssertEqual(input.process(bitmap: idle, from: .right, connected: both, now: 0.18), [])
        XCTAssertEqual(input.process(bitmap: rightShift, from: .right, connected: both, now: 0.27), [.shiftRight])
    }

    func testRelayedPressIsIgnoredWhenOwnerConnected() {
        var input = ClickInputProcessor(holdToRepeat: false)
        let both: Set<ClickSide> = [.left, .right]
        XCTAssertEqual(input.process(bitmap: rightShift, from: .right, connected: both, now: 0), [.shiftRight])
        // The left half relays the same press.
        XCTAssertEqual(input.process(bitmap: rightShift, from: .left, connected: both, now: 0.01), [])
    }

    func testRelayedPressIsAcceptedWhenOwnerMissing() {
        var input = ClickInputProcessor(holdToRepeat: false)
        XCTAssertEqual(input.process(bitmap: rightShift, from: .left, connected: [.left], now: 0), [.shiftRight])
        XCTAssertEqual(input.process(bitmap: leftShift, from: .left, connected: [.left], now: 1), [.shiftLeft])
    }

    func testHoldToRepeat() {
        var input = ClickInputProcessor(holdToRepeat: true)
        let both: Set<ClickSide> = [.left, .right]
        var fired = 0
        var t = 0.0
        while t <= 1.0 {
            fired += input.process(bitmap: rightShift, from: .right, connected: both, now: t).count
            t += 0.09
        }
        // 1 initial press + repeats every ≥0.2 s after the 0.5 s delay.
        XCTAssertEqual(fired, 3)
    }

    func testFivePressesEachWay() {
        var input = ClickInputProcessor(holdToRepeat: false)
        let both: Set<ClickSide> = [.left, .right]
        var gear = 12
        var t = 0.0
        for (bitmap, side, delta) in [(rightShift, ClickSide.right, 1), (leftShift, ClickSide.left, -1)] {
            for _ in 0..<5 {
                // The left half also relays the right half's presses.
                let frameSides: [ClickSide] = side == .right ? [.right, .left] : [.left]
                for frameSide in frameSides {
                    for button in input.process(bitmap: bitmap, from: frameSide, connected: both, now: t) {
                        if button == .shiftRight || button == .shiftLeft { gear += delta }
                    }
                    _ = input.process(bitmap: idle, from: frameSide, connected: both, now: t + 0.1)
                }
                t += 0.5
            }
            if delta > 0 { XCTAssertEqual(gear, 17) }
        }
        XCTAssertEqual(gear, 12)
    }
}

final class PhysicsTests: XCTestCase {
    func testSpeedRoundTrip() {
        let speed = RoadPhysics.speed(forPower: 200, gradePercent: 0, totalMassKg: 85)
        XCTAssertEqual(RoadPhysics.power(atSpeed: speed, gradePercent: 0, totalMassKg: 85), 200, accuracy: 0.5)
        XCTAssertGreaterThan(speed * 3.6, 25)
        XCTAssertLessThan(speed * 3.6, 40)
    }

    func testClimbIsSlowerAndDescentIsFaster() {
        let flat = RoadPhysics.speed(forPower: 150, gradePercent: 0, totalMassKg: 85)
        XCTAssertLessThan(RoadPhysics.speed(forPower: 150, gradePercent: 5, totalMassKg: 85), flat)
        XCTAssertGreaterThan(RoadPhysics.speed(forPower: 150, gradePercent: -3, totalMassKg: 85), flat)
        XCTAssertEqual(RoadPhysics.speed(forPower: 0, gradePercent: 2, totalMassKg: 85), 0)
        XCTAssertGreaterThan(RoadPhysics.speed(forPower: 0, gradePercent: -5, totalMassKg: 85), 5)
    }

    func testVirtualSpeedFollowsGearAndCadence() {
        // Flywheel speed for a given cadence with a 34T ring on the 14T Zwift Cog.
        func flywheel(rpm: Double) -> Double { rpm / 60 * 34 / 14 * 2.096 }
        func kmh(gear: Int, rpm: Double) -> Double {
            RoadPhysics.virtualSpeed(flywheelSpeed: flywheel(rpm: rpm), gearRatio: GearTable.ratio(forGear: gear),
                                     chainringTeeth: 34, cogTeeth: 14) * 3.6
        }
        // speed = cadence × virtual ratio × wheel circumference
        XCTAssertEqual(kmh(gear: 12, rpm: 90), 90.0 / 60 * 2.40 * 2.096 * 3.6, accuracy: 0.01)
        // Harder gear at lower cadence: 12 @ 90 rpm ≈ 27.2 km/h, 16 @ 75 rpm ≈ 30.6 km/h.
        XCTAssertEqual(kmh(gear: 12, rpm: 90), 27.2, accuracy: 0.1)
        XCTAssertEqual(kmh(gear: 16, rpm: 75), 30.6, accuracy: 0.1)
        // Same cadence, easier gear → slower, even where the trainer's ~40 W floor makes power equal.
        XCTAssertLessThan(kmh(gear: 4, rpm: 85), kmh(gear: 8, rpm: 85))
    }

    func testCadenceEstimate() {
        // 26.1 km/h with 34T and the 14T Zwift Cog ≈ 85 rpm.
        let rpm = RoadPhysics.cadence(flywheelSpeed: 26.1 / 3.6, chainringTeeth: 34, cogTeeth: 14,
                                      wheelCircumferenceMm: 2096)
        XCTAssertEqual(rpm, 85, accuracy: 1)
    }

    func testNormalizedPowerOfSteadyEffort() {
        var metrics = RideMetrics()
        for t in 0..<120 {
            metrics.add(RideSample(t: t, power: 200, heartRate: 140, cadence: 90, speed: 9, gear: 12, grade: 0))
        }
        XCTAssertEqual(metrics.averagePower, 200)
        XCTAssertEqual(metrics.normalizedPower, 200)
        XCTAssertEqual(metrics.averageHeartRate, 140)
        XCTAssertEqual(metrics.distance, 1080, accuracy: 0.001)
        XCTAssertEqual(metrics.trainingStressScore(ftp: 200), 100.0 * 120 / 3600, accuracy: 0.01)
    }
}

final class WorkoutTests: XCTestCase {
    private let zones = HeartRateZones(method: .percentOfMax, maxHeartRate: 190, restingHeartRate: 60,
                                       boundaries: HeartRateZones.defaultBoundaries)

    func testLibraryDurations() {
        // 10 min warm-up + 4 × 4 min + 3 × 3 min + 5 min cool-down
        XCTAssertEqual(WorkoutLibrary.norwegian4x4.duration, 600 + 4 * 240 + 3 * 180 + 300)
        // 10 min warm-up + 3 × 13 × 45 s + 2 × 3 min + 5 min cool-down
        XCTAssertEqual(WorkoutLibrary.ronnestad3015.duration, 600 + 3 * 13 * 45 + 2 * 180 + 300)
        XCTAssertEqual(WorkoutLibrary.zone2(minutes: 60).duration, 300 + 3600 + 300)
        XCTAssertTrue(WorkoutLibrary.zone2(minutes: 45).isHeartRateControlled)
        XCTAssertFalse(WorkoutLibrary.fiveByThree.isHeartRateControlled)
    }

    func testStepsAdvanceAndTargets() {
        let controller = WorkoutController()
        let workout = Workout(id: "t", name: "Test", category: .vo2max, summary: "", steps: [
            WorkoutStep(label: "A", duration: 3, target: .power(0.5)),
            WorkoutStep(label: "B", duration: 2, target: .power(1.1)),
        ])
        controller.start(workout, ftp: 250)
        XCTAssertEqual(controller.targetWatts(ftp: 250), 125)
        XCTAssertNil(controller.advance(heartRate: nil, zones: zones, ftp: 250))
        XCTAssertNil(controller.advance(heartRate: nil, zones: zones, ftp: 250))
        XCTAssertEqual(controller.advance(heartRate: nil, zones: zones, ftp: 250), .stepChanged)
        XCTAssertEqual(controller.step?.label, "B")
        XCTAssertEqual(controller.targetWatts(ftp: 250), 275)
        controller.nudge(10)
        XCTAssertEqual(controller.targetWatts(ftp: 250), 285)
        XCTAssertNil(controller.advance(heartRate: 180, zones: zones, ftp: 250))
        XCTAssertEqual(controller.secondsInZone5, 1) // 180 ≥ 171 (90 % of 190)
        XCTAssertEqual(controller.advance(heartRate: nil, zones: zones, ftp: 250), .finished)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.targetWatts(ftp: 250))
    }

    func testSkip() {
        let controller = WorkoutController()
        controller.start(WorkoutLibrary.norwegian4x4, ftp: 200)
        XCTAssertTrue(controller.skip())
        XCTAssertEqual(controller.stepIndex, 1)
        XCTAssertEqual(controller.elapsed, 300)
    }

    func testHeartRateControlLowersPowerWhenHeartRateHigh() {
        let controller = WorkoutController()
        let workout = Workout(id: "z2", name: "Z2", category: .zone2, summary: "", steps: [
            WorkoutStep(label: "Zone 2", duration: 600, target: .heartRateZone(2)),
        ])
        controller.start(workout, ftp: 250) // starts at 60 % FTP = 150 W
        let start = controller.heartRateWatts
        for _ in 0..<60 { _ = controller.advance(heartRate: 160, zones: zones, ftp: 250) } // Zone 2 = 114–132
        XCTAssertLessThan(controller.heartRateWatts, start)
        let lowered = controller.heartRateWatts
        for _ in 0..<60 { _ = controller.advance(heartRate: 100, zones: zones, ftp: 250) }
        XCTAssertGreaterThan(controller.heartRateWatts, lowered)
        // In band: no change, and counted as time in target.
        let held = controller.heartRateWatts
        for _ in 0..<20 { _ = controller.advance(heartRate: 123, zones: zones, ftp: 250) }
        XCTAssertEqual(controller.heartRateWatts, held, accuracy: 0.8 * 1 + 0.001)
        XCTAssertEqual(controller.secondsInHeartRateTarget, 20)
        // No heart rate: hold power.
        let before = controller.heartRateWatts
        for _ in 0..<30 { _ = controller.advance(heartRate: nil, zones: zones, ftp: 250) }
        XCTAssertTrue(controller.missingHeartRate)
        XCTAssertEqual(controller.heartRateWatts, before)
    }

    func testHeartRateZones() {
        XCTAssertEqual(zones.limits, [114, 133, 152, 171])
        XCTAssertEqual(zones.zone(for: 100)?.number, 1)
        XCTAssertEqual(zones.zone(for: 120)?.number, 2)
        XCTAssertEqual(zones.zone(for: 171)?.number, 5)
        XCTAssertEqual(zones.lowerLimit(ofZone: 2), 114)
        XCTAssertEqual(zones.upperLimit(ofZone: 2), 133)
        XCTAssertEqual(zones.upperLimit(ofZone: 5), 190)

        // Karvonen: 60 + 0.6 × (190 − 60) = 138
        let reserve = HeartRateZones(method: .heartRateReserve, maxHeartRate: 190, restingHeartRate: 60,
                                     boundaries: HeartRateZones.defaultBoundaries)
        XCTAssertEqual(reserve.lowerLimit(ofZone: 2), 138)
    }

    func testRideAnalysis() {
        // 30 min at 60 % FTP with heart rate in Zone 2 and steady.
        let samples = (0..<1800).map {
            RideSample(t: $0, power: 150, heartRate: 125, cadence: 85, speed: 8, gear: 12, grade: 0)
        }
        let analysis = RideAnalysis(samples: samples, zones: zones, ftp: 250)
        XCTAssertEqual(analysis.heartRateZoneSeconds, [0, 1800, 0, 0, 0])
        // 150 W × 1800 s = 270 kJ mechanical → ≈ 269 kcal metabolic at 24 % efficiency.
        XCTAssertEqual(analysis.kilocalories, 270_000 / 0.24 / 4184, accuracy: 0.5)
        XCTAssertGreaterThan(analysis.fatGrams, 10)
        XCTAssertEqual(analysis.decouplingPercent ?? 99, 0, accuracy: 0.001)
        XCTAssertGreaterThan(RideAnalysis.fatFraction(intensity: 0.6), RideAnalysis.fatFraction(intensity: 1.1))
    }
}
