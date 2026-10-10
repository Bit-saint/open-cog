import Foundation

enum ClickSide: String, Codable, CaseIterable {
    case left, right

    /// First manufacturer-data byte after the Zwift company ID (0x094A).
    init?(deviceType: UInt8) {
        switch deviceType {
        case 0x0B: self = .left
        case 0x0A: self = .right
        default: return nil
        }
    }
}

/// Button bits of the Zwift Ride keymap. The Click v2 implements a subset.
enum ZwiftButton: Int, CaseIterable {
    case left = 0, up = 1, right = 2, down = 3
    case a = 4, b = 5, y = 6, z = 7
    case shiftLeft = 8, shiftDownLeft = 9, powerUpLeft = 10, onOffLeft = 11
    case shiftRight = 12, shiftDownRight = 13, powerUpRight = 14, onOffRight = 15

    var mask: UInt32 { 1 << UInt32(rawValue) }

    /// The half that physically carries the button. The left half relays the right half's
    /// presses, so a bit is accepted only from its owner while the owner is connected.
    var owner: ClickSide {
        switch self {
        case .left, .up, .right, .down, .shiftLeft, .shiftDownLeft, .powerUpLeft, .onOffLeft:
            return .left
        case .a, .b, .y, .z, .shiftRight, .shiftDownRight, .powerUpRight, .onOffRight:
            return .right
        }
    }

    /// Buttons that auto-repeat while held.
    var repeats: Bool {
        switch self {
        case .shiftLeft, .shiftRight, .up, .down: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .left: return "D-pad Left"
        case .up: return "D-pad Up"
        case .right: return "D-pad Right"
        case .down: return "D-pad Down"
        case .a: return "A"
        case .b: return "B"
        case .y: return "Y"
        case .z: return "Z"
        case .shiftLeft: return "Left shift"
        case .shiftRight: return "Right shift"
        default: return "Button \(rawValue)"
        }
    }
}

/// Turns raw Click bitmaps into button presses: edge detection, the relay (owner) filter
/// and hold-to-repeat. Pure logic so it can be unit tested.
struct ClickInputProcessor {
    var repeatDelay: TimeInterval = 0.5
    var repeatInterval: TimeInterval = 0.2
    var holdToRepeat = true

    private var previous: [ClickSide: UInt32] = [:]
    private var heldSince: [ZwiftButton: TimeInterval] = [:]
    private var lastFired: [ZwiftButton: TimeInterval] = [:]

    init(holdToRepeat: Bool = true) {
        self.holdToRepeat = holdToRepeat
    }

    /// - Parameters:
    ///   - bitmap: raw active-low bitmap from a `0x23` frame.
    ///   - side: the half the frame came from.
    ///   - connected: halves currently connected (and handshaken).
    ///   - now: monotonic timestamp in seconds.
    /// - Returns: presses to act on, in bit order.
    mutating func process(bitmap: UInt32, from side: ClickSide, connected: Set<ClickSide>,
                          now: TimeInterval) -> [ZwiftButton] {
        let pressedNow = ~bitmap & 0xFFFF
        let pressedPrev = ~(previous[side] ?? 0xFFFF_FFFF) & 0xFFFF
        previous[side] = bitmap

        var fired: [ZwiftButton] = []
        for button in ZwiftButton.allCases {
            if button.owner != side && connected.contains(button.owner) { continue } // relayed duplicate
            let isDown = pressedNow & button.mask != 0
            let wasDown = pressedPrev & button.mask != 0

            if isDown && !wasDown {
                fired.append(button)
                heldSince[button] = now
                lastFired[button] = now
            } else if isDown, holdToRepeat, button.repeats,
                      let start = heldSince[button], let last = lastFired[button],
                      now - start >= repeatDelay, now - last >= repeatInterval {
                fired.append(button)
                lastFired[button] = now
            } else if !isDown && wasDown {
                heldSince[button] = nil
                lastFired[button] = nil
            }
        }
        return fired
    }

    /// Forget a half's last state, e.g. after it disconnects.
    mutating func reset(side: ClickSide) {
        previous[side] = nil
        heldSince = heldSince.filter { $0.key.owner != side }
        lastFired = lastFired.filter { $0.key.owner != side }
    }
}
