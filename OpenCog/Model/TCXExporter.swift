import Foundation

/// Writes a ride as a Garmin TCX file (with power) that Strava, Garmin Connect,
/// TrainingPeaks and intervals.icu can import.
enum TCXExporter {
    static func makeTCX(for ride: RideRecord, samples: [RideSample]) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let start = iso.string(from: ride.date)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" \
        xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
          <Activities>
            <Activity Sport="Biking">
              <Id>\(start)</Id>
              <Lap StartTime="\(start)">
                <TotalTimeSeconds>\(ride.duration)</TotalTimeSeconds>
                <DistanceMeters>\(String(format: "%.1f", ride.distance))</DistanceMeters>
                <Calories>\(ride.kilojoules)</Calories>

        """
        if let avg = ride.averageHeartRate {
            xml += "        <AverageHeartRateBpm><Value>\(avg)</Value></AverageHeartRateBpm>\n"
        }
        if let max = ride.maxHeartRate {
            xml += "        <MaximumHeartRateBpm><Value>\(max)</Value></MaximumHeartRateBpm>\n"
        }
        xml += """
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>

        """

        var distance = 0.0
        for sample in samples {
            distance += sample.speed
            let time = iso.string(from: ride.date.addingTimeInterval(TimeInterval(sample.t)))
            xml += "          <Trackpoint><Time>\(time)</Time>"
            xml += "<DistanceMeters>\(String(format: "%.1f", distance))</DistanceMeters>"
            if let hr = sample.heartRate {
                xml += "<HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>"
            }
            xml += "<Cadence>\(min(sample.cadence, 254))</Cadence>"
            xml += "<Extensions><ns3:TPX><ns3:Speed>\(String(format: "%.2f", sample.speed))</ns3:Speed>"
            xml += "<ns3:Watts>\(sample.power)</ns3:Watts></ns3:TPX></Extensions></Trackpoint>\n"
        }

        xml += """
                </Track>
              </Lap>
              <Creator xsi:type="Device_t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <Name>OpenCog</Name>
              </Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>

        """
        return xml
    }

    static func writeFile(for ride: RideRecord, samples: [RideSample]) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCog_\(formatter.string(from: ride.date)).tcx")
        try makeTCX(for: ride, samples: samples).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
