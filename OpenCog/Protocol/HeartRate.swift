import Foundation

/// Bluetooth SIG Heart Rate Measurement (0x2A37). Garmin watches use this format when
/// "Broadcast Heart Rate" is enabled.
struct HeartRateMeasurement: Equatable {
    var bpm: Int
    /// nil when the sensor doesn't support contact detection.
    var sensorContact: Bool?

    init?(_ data: Data) {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        if flags & 0x01 == 0 {
            guard bytes.count >= 2 else { return nil }
            bpm = Int(bytes[1])
        } else {
            guard bytes.count >= 3 else { return nil }
            bpm = Int(bytes[1]) | Int(bytes[2]) << 8
        }
        let contactSupported = flags & 0x04 != 0
        sensorContact = contactSupported ? (flags & 0x02 != 0) : nil
    }
}
