import Foundation
import Observation

enum TrainerMode: String, CaseIterable, Identifiable {
    case sim, erg
    var id: String { rawValue }
    var title: String { self == .sim ? "Gears" : "ERG" }
    var subtitle: String { self == .sim ? "Virtual shifting on a simulated road" : "Trainer holds target power" }
}

enum RideState: Equatable {
    case idle, riding, paused, autoPaused

    var isActive: Bool { self != .idle }
}

/// A short on-screen confirmation of a Click button action.
struct ControlFeedback: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var systemImage: String
}

/// One second of live data for the rolling chart (kept even when not recording).
struct LivePoint: Identifiable, Equatable {
    var id: Date { time }
    var time: Date
    var power: Int
    var heartRate: Int?
}

/// The app's "gearbox" and ride recorder: holds the virtual gear, grade and ERG target,
/// keeps the trainer in sync, and records ride samples once per second.
@Observable
final class RideEngine {
    let bluetooth: BluetoothManager
    let settings: AppSettings

    // MARK: Live values
    private(set) var power = 0
    private(set) var powerAverage3s = 0
    private(set) var flywheelSpeed = 0.0
    private(set) var cadence = 0
    private(set) var heartRate: Int?
    private(set) var virtualSpeed = 0.0
    private(set) var liveHistory: [LivePoint] = []

    // MARK: Trainer control
    private(set) var mode: TrainerMode = .sim
    private(set) var gear: Int
    private(set) var grade = 0.0
    private(set) var ergTarget = 150
    private(set) var feedback: ControlFeedback?

    static let gradeRange = -10.0...15.0
    static let gradeStep = 0.5
    static let ergRange = 50...600 // trainer's advertised power range

    // MARK: Recording
    private(set) var state: RideState = .idle
    private(set) var startDate: Date?
    private(set) var metrics = RideMetrics()
    private(set) var samples: [RideSample] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var lastRidingData = Date.distantPast
    @ObservationIgnored private var lastHeartRateDate = Date.distantPast
    @ObservationIgnored private var recentPower: [Int] = []
    @ObservationIgnored private var stoppedSeconds = 0
    @ObservationIgnored private var lastPhysicalCommand: Data?

    init(bluetooth: BluetoothManager, settings: AppSettings) {
        self.bluetooth = bluetooth
        self.settings = settings
        gear = min(max(settings.startingGear, GearTable.range.lowerBound), GearTable.range.upperBound)

        bluetooth.holdToRepeat = settings.holdToRepeat
        bluetooth.onRidingData = { [weak self] in self?.receive($0) }
        bluetooth.onHeartRate = { [weak self] in self?.receiveHeartRate($0) }
        bluetooth.onButtons = { [weak self] presses in presses.forEach { self?.handle($0) } }
        bluetooth.onTrainerReady = { [weak self] in self?.pushTrainerState() }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    // MARK: Controls

    func shiftUp() { shift(by: 1) }
    func shiftDown() { shift(by: -1) }

    func shift(by delta: Int) {
        switch mode {
        case .sim:
            let newGear = min(max(gear + delta, GearTable.range.lowerBound), GearTable.range.upperBound)
            guard newGear != gear else { return }
            gear = newGear
            sendPhysical()
        case .erg:
            // Gear commands are ignored in ERG, so the shifters nudge the target instead.
            setErgTarget(ergTarget + delta * 5)
        }
    }

    func adjustGrade(by delta: Double) { setGrade(grade + delta) }

    func setGrade(_ value: Double) {
        let stepped = (value / Self.gradeStep).rounded() * Self.gradeStep
        let clamped = min(max(stepped, Self.gradeRange.lowerBound), Self.gradeRange.upperBound)
        guard clamped != grade else { return }
        grade = clamped
        if mode == .sim { sendSimulation() }
    }

    func adjustErgTarget(by delta: Int) { setErgTarget(ergTarget + delta) }

    func setErgTarget(_ watts: Int) {
        let clamped = min(max(watts, Self.ergRange.lowerBound), Self.ergRange.upperBound)
        guard clamped != ergTarget else { return }
        ergTarget = clamped
        if mode == .erg { bluetooth.sendToTrainer(Zwift.ergCommand(watts: ergTarget)) }
    }

    func setMode(_ newMode: TrainerMode) {
        guard newMode != mode else { return }
        mode = newMode
        pushTrainerState()
    }

    /// Sends the full current state. Simulation/Physical also take the trainer out of ERG.
    func pushTrainerState() {
        switch mode {
        case .sim:
            sendSimulation()
            lastPhysicalCommand = nil
            sendPhysical()
        case .erg:
            bluetooth.sendToTrainer(Zwift.ergCommand(watts: ergTarget))
        }
    }

    private func sendSimulation() {
        bluetooth.sendToTrainer(Zwift.simulationCommand(gradePercent: grade))
    }

    private func sendPhysical() {
        let command = Zwift.physicalCommand(gearRatio: GearTable.ratio(forGear: gear),
                                            bikeKg: settings.bikeWeightKg,
                                            riderKg: settings.riderWeightKg)
        lastPhysicalCommand = command
        bluetooth.sendToTrainer(command)
    }

    // MARK: Ride lifecycle

    func start() {
        guard state == .idle else { return }
        metrics = RideMetrics()
        samples = []
        startDate = Date()
        stoppedSeconds = 0
        state = .riding
    }

    func pause() {
        guard state == .riding || state == .autoPaused else { return }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        stoppedSeconds = 0
        state = .riding
    }

    func toggleRide() {
        switch state {
        case .idle: start()
        case .riding, .autoPaused: pause()
        case .paused: resume()
        }
    }

    /// Ends the ride and returns a record to save, or nil if it was too short to keep.
    func finish() -> RideRecord? {
        defer { reset() }
        guard let startDate, metrics.seconds >= 10 else { return nil }
        return RideRecord(startDate: startDate, metrics: metrics, samples: samples, ftp: settings.ftp)
    }

    func discard() { reset() }

    private func reset() {
        state = .idle
        startDate = nil
        metrics = RideMetrics()
        samples = []
    }

    // MARK: Inputs

    private func receive(_ data: RidingData) {
        lastRidingData = Date()
        power = data.power
        flywheelSpeed = data.flywheelSpeed
        cadence = Int(RoadPhysics.cadence(flywheelSpeed: data.flywheelSpeed,
                                          chainringTeeth: settings.chainringTeeth,
                                          cogTeeth: settings.cogTeeth,
                                          wheelCircumferenceMm: settings.wheelCircumferenceMm).rounded())
    }

    private func receiveHeartRate(_ bpm: Int?) {
        heartRate = bpm
        if bpm != nil { lastHeartRateDate = Date() }
    }

    private func handle(_ button: ZwiftButton) {
        switch button {
        case .shiftRight:
            shiftUp()
            showFeedback(for: button)
        case .shiftLeft:
            shiftDown()
            showFeedback(for: button)
        case .up:
            if mode == .sim { adjustGrade(by: Self.gradeStep) } else { adjustErgTarget(by: 10) }
            showFeedback(for: button)
        case .down:
            if mode == .sim { adjustGrade(by: -Self.gradeStep) } else { adjustErgTarget(by: -10) }
            showFeedback(for: button)
        case .a:
            toggleRide()
            showFeedback(for: button)
        case .y:
            setMode(mode == .sim ? .erg : .sim)
            showFeedback(for: button)
        default:
            break
        }
    }

    private func showFeedback(for button: ZwiftButton) {
        switch button {
        case .shiftRight, .shiftLeft:
            feedback = mode == .sim
                ? ControlFeedback(text: "Gear \(gear)", systemImage: button == .shiftRight ? "arrow.up" : "arrow.down")
                : ControlFeedback(text: "\(ergTarget) W", systemImage: "target")
        case .up, .down:
            feedback = mode == .sim
                ? ControlFeedback(text: "Grade \(Format.grade(grade))", systemImage: "mountain.2")
                : ControlFeedback(text: "\(ergTarget) W", systemImage: "target")
        case .a:
            switch state {
            case .riding: feedback = ControlFeedback(text: "Ride started", systemImage: "play.fill")
            case .paused: feedback = ControlFeedback(text: "Paused", systemImage: "pause.fill")
            default: break
            }
        case .y:
            feedback = ControlFeedback(text: mode == .sim ? "Gears mode" : "ERG mode", systemImage: "arrow.triangle.2.circlepath")
        default:
            break
        }
    }

    // MARK: 1 Hz loop

    private func tick() {
        tickCount += 1
        let now = Date()

        if now.timeIntervalSince(lastRidingData) > 3 {
            power = 0
            flywheelSpeed = 0
            cadence = 0
        }
        if heartRate != nil, now.timeIntervalSince(lastHeartRateDate) > 5 {
            heartRate = nil
        }
        bluetooth.holdToRepeat = settings.holdToRepeat

        // Keep the trainer in sync: resend the mode command every 2 s, and the gear
        // whenever it (or a mass setting) changed.
        if bluetooth.isReady(.trainer) {
            switch mode {
            case .sim:
                if tickCount % 2 == 0 { sendSimulation() }
                let physical = Zwift.physicalCommand(gearRatio: GearTable.ratio(forGear: gear),
                                                     bikeKg: settings.bikeWeightKg,
                                                     riderKg: settings.riderWeightKg)
                if physical != lastPhysicalCommand { sendPhysical() }
            case .erg:
                if tickCount % 2 == 0 { bluetooth.sendToTrainer(Zwift.ergCommand(watts: ergTarget)) }
            }
        }

        recentPower.append(power)
        if recentPower.count > 3 { recentPower.removeFirst() }
        powerAverage3s = recentPower.reduce(0, +) / max(recentPower.count, 1)

        let roadGrade = mode == .sim ? grade : 0
        let target = RoadPhysics.speed(forPower: Double(power), gradePercent: roadGrade,
                                       totalMassKg: settings.totalMassKg)
        virtualSpeed += (target - virtualSpeed) * 0.35
        if target < 0.1 && virtualSpeed < 0.3 { virtualSpeed = 0 }

        liveHistory.append(LivePoint(time: now, power: power, heartRate: heartRate))
        if liveHistory.count > 300 { liveHistory.removeFirst(liveHistory.count - 300) }

        record()
    }

    private func record() {
        guard state == .riding || state == .autoPaused else { return }

        let moving = power > 0 || flywheelSpeed >= 0.5
        stoppedSeconds = moving ? 0 : stoppedSeconds + 1
        if settings.autoPause {
            if state == .riding && stoppedSeconds > 3 { state = .autoPaused }
            if state == .autoPaused && moving { state = .riding }
        } else if state == .autoPaused {
            state = .riding
        }
        guard state == .riding else { return }

        let sample = RideSample(t: metrics.seconds, power: power, heartRate: heartRate, cadence: cadence,
                                speed: virtualSpeed, gear: gear, grade: mode == .sim ? grade : 0,
                                ergTarget: mode == .erg ? ergTarget : nil)
        samples.append(sample)
        metrics.add(sample)
    }
}
