import Foundation

enum DiaBoxLibreParser {
    struct Diagnostics {
        let framByteCount: Int
        let didParse: Bool
        let sensorTimeInMinutes: Int?
        let currentGlucose: Double?
        let currentTimestamp: Date?
        let currentRateOfChange: Double?
        let currentRawGlucose: Double?
        let currentRecordNumber: Int?
        let currentDataQuality: Int?
        let currentAccepted: Bool
        let historyCount: Int
        let rejectedHistoryQualityCount: Int
        let rejectedHistoryRangeCount: Int
        let rejectedHistoryDateCount: Int
    }

    static func parse(_ sensorData: SensorData) -> LibreTransmitterManagerV3.GlucoseArrayWithPrediction {
        parseWithDiagnostics(sensorData).readings
    }

    static func parseWithDiagnostics(_ sensorData: SensorData) -> (readings: LibreTransmitterManagerV3.GlucoseArrayWithPrediction, diagnostics: Diagnostics) {
        guard let result = DiaBoxGlucoseAlgorithm.parseFRAM(Data(sensorData.bytes), read: sensorData.date) else {
            let diagnostics = Diagnostics(
                framByteCount: sensorData.bytes.count,
                didParse: false,
                sensorTimeInMinutes: nil,
                currentGlucose: nil,
                currentTimestamp: nil,
                currentRateOfChange: nil,
                currentRawGlucose: nil,
                currentRecordNumber: nil,
                currentDataQuality: nil,
                currentAccepted: false,
                historyCount: 0,
                rejectedHistoryQualityCount: 0,
                rejectedHistoryRangeCount: 0,
                rejectedHistoryDateCount: 0
            )
            return ((trends: [], historical: [], prediction: []), diagnostics)
        }

        let current = result.current.map {
            LibreGlucose(
                unsmoothedGlucose: $0.glucose,
                glucoseDouble: $0.glucose,
                rateOfChange: $0.rateOfChange,
                timestamp: $0.timestamp
            )
        }

        let historical = result.history.map {
            LibreGlucose(
                unsmoothedGlucose: $0.glucose,
                glucoseDouble: $0.glucose,
                timestamp: $0.timestamp
            )
        }

        let readings: LibreTransmitterManagerV3.GlucoseArrayWithPrediction = (trends: current.map { [$0] } ?? [], historical: historical, prediction: [])
        let diagnostics = Diagnostics(
            framByteCount: sensorData.bytes.count,
            didParse: true,
            sensorTimeInMinutes: result.sensorTimeInMinutes,
            currentGlucose: result.current?.glucose,
            currentTimestamp: result.current?.timestamp,
            currentRateOfChange: result.current?.rateOfChange,
            currentRawGlucose: result.currentRawGlucose,
            currentRecordNumber: result.currentRecordNumber,
            currentDataQuality: result.currentDataQuality,
            currentAccepted: result.current != nil,
            historyCount: result.history.count,
            rejectedHistoryQualityCount: result.rejectedHistoryQualityCount,
            rejectedHistoryRangeCount: result.rejectedHistoryRangeCount,
            rejectedHistoryDateCount: result.rejectedHistoryDateCount
        )
        return (readings, diagnostics)
    }
}
