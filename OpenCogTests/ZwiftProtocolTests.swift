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
