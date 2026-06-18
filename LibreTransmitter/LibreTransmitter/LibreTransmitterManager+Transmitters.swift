//
//  LibreTransmitterManager+Transmitters.swift
//  LibreTransmitter
//
//  Created by LoopKit Authors on 25/04/2022.
//  Copyright © 2022 Mark Wilson. All rights reserved.
//

import Foundation
import LoopKit

// MARK: - Bluetooth transmitter data
extension LibreTransmitterManagerV3 {

    public func noLibreTransmitterSelected() {
        NotificationHelper.sendNoTransmitterSelectedNotification()
    }

    public func libreTransmitterDidUpdate(with sensorData: SensorData, and Device: LibreTransmitterMetadata) {

        self.logger.debug("got sensordata: \(String(describing: sensorData)), bytescount: \( sensorData.bytes.count), bytes: \(sensorData.bytes)")
        var sensorData = sensorData

        NotificationHelper.sendLowBatteryNotificationIfNeeded(device: Device)
        self.setObservables(sensorData: nil, bleData: nil, metaData: Device)

         if !sensorData.isLikelyLibre1FRAM {
            if let patchInfo = sensorData.patchInfo {
                let sensorType = SensorType(patchInfo: patchInfo)
                let needsDecryption = [SensorType.libre2, .libreUS14day].contains(sensorType)
                if needsDecryption, let uid = Device.uid {
                    sensorData.decrypt(patchInfo: patchInfo, uid: uid)
                }
            } else {
                logger.debug("Sensor type was incorrect, and no decryption of sensor was possible")
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.encryptedSensor))
                return
            }
        }

        let typeDesc = Device.sensorType().debugDescription

        logger.debug("Transmitter connected to libresensor of type \(typeDesc). Details:  \(Device.description)")

        tryPersistSensorData(with: sensorData)

        NotificationHelper.sendInvalidSensorNotificationIfNeeded(sensorData: sensorData)
        NotificationHelper.sendInvalidChecksumIfDeveloper(sensorData)

        logDeviceCommunication("Sensor gate crc valid=\(sensorData.hasValidCRCs) header=\(sensorData.hasValidHeaderCRC) body=\(sensorData.hasValidBodyCRC) footer=\(sensorData.hasValidFooterCRC) state=\(sensorData.state.description) minutesSinceStart=\(sensorData.minutesSinceStart) sensorType=\(typeDesc)", type: sensorData.hasValidCRCs ? .receive : .error)
        guard sensorData.hasValidCRCs else {
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.checksumValidationError))
            }

            logger.debug("did not get sensordata with valid crcs")
            return
        }

        NotificationHelper.sendSensorExpireAlertIfNeeded(sensorData: sensorData)

        let isAllowedSensorState = sensorData.state == .ready || sensorData.state == .starting
        logDeviceCommunication("Sensor gate state allowed=\(isAllowedSensorState) state=\(sensorData.state.description) minutesSinceStart=\(sensorData.minutesSinceStart) maxMinutesWearTime=\(sensorData.maxMinutesWearTime)", type: isAllowedSensorState ? .receive : .error)
        guard isAllowedSensorState else {
            logger.debug("got sensordata with valid crcs, but sensor is either expired or failed")
            self.delegateQueue.async {
                self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(LibreError.expiredSensor))
            }
            return
        }

        logger.debug("got sensordata with valid crcs, sensor was ready")
        // self.lastValidSensorData = sensorData

        
        verifySensorChange(for: sensorData.uuid, activatedAt: Date() - TimeInterval(minutes: Double(sensorData.minutesSinceStart)))
        
        

        self.handleGoodReading(data: sensorData) { [weak self] error, glucoseArrayWithPrediction in
            guard let self else {
                print(" handleGoodReading could not lock on self, aborting")
                return
            }
            if let error {
                self.logger.error(" handleGoodReading returned with error: \(error.errorDescription)")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .error(error))
                }
                return
            }

            guard let glucose = glucoseArrayWithPrediction?.trends else {
                self.logger.debug("handleGoodReading returned with no data")
                self.delegateQueue.async {
                    self.cgmManagerDelegate?.cgmManager(self, hasNew: .noData)
                }
                return
            }

            let prediction = glucoseArrayWithPrediction?.prediction

            var newGlucoses : [NewGlucoseSample] = []
            
            let startDate = self.getStartDateForFilter()
            let rawTrendCount = glucose.count
            let rawHistoricalCount = glucoseArrayWithPrediction?.historical.count ?? 0

            // Since trends have a spacing of 1 minute between them, we use that to calculate trend arrows
            var trends = self.glucosesToSamplesFilter(glucose, startDate: startDate)
            let filteredTrendCount = trends.count
            
            // But since Loop only supports 1 glucose reading
            // every 5 minutes, we remove all readings except the newest
            if let newest = trends.first {
                trends = [newest]
            }
            
            // Historical readings have a spacing of 15 minutes between them,
            // trend arrow calculation doesn't make that much sense
            var filteredHistoricalCount = 0
            if let historical = glucoseArrayWithPrediction?.historical {
                let historical2 = self.glucosesToSamplesFilter(historical, startDate: startDate, calculateTrends: false)
                filteredHistoricalCount = historical2.count
                if !historical.isEmpty {
                    newGlucoses = historical2
                }
                
            }
            newGlucoses += trends
            self.logger.debug("DiaBox filter result: startDate=\(String(describing: startDate), privacy: .public), currentRaw=\(rawTrendCount, privacy: .public), currentFiltered=\(filteredTrendCount, privacy: .public), currentEmitted=\(trends.count, privacy: .public), historyRaw=\(rawHistoricalCount, privacy: .public), historyFiltered=\(filteredHistoricalCount, privacy: .public), totalEmitted=\(newGlucoses.count, privacy: .public)")
            self.logDeviceCommunication("DiaBox filter currentRaw=\(rawTrendCount) currentFiltered=\(filteredTrendCount) currentEmitted=\(trends.count) historyRaw=\(rawHistoricalCount) historyFiltered=\(filteredHistoricalCount) totalEmitted=\(newGlucoses.count)", type: .receive)
            self.logDeviceCommunication("DiaBox storage candidate current=\(trends.count) history=\(filteredHistoricalCount) total=\(newGlucoses.count) startDate=\(String(describing: startDate))", type: newGlucoses.isEmpty ? .error : .receive)

            if newGlucoses.isEmpty {
                self.countTimesWithoutData &+= 1
            } else {
                self.latestBackfill = glucose.max { $0.startDate < $1.startDate }
                self.logger.debug("latestbackfill set to \(self.latestBackfill.debugDescription)")
                self.countTimesWithoutData = 0
            }
            self.logger.debug("DiaBox final result: totalEmitted=\(newGlucoses.count, privacy: .public), countTimesWithoutData=\(self.countTimesWithoutData, privacy: .public), willReport=\(self.countTimesWithoutData > 1 ? "noValidSensorData" : (newGlucoses.isEmpty ? "noData" : "newData"), privacy: .public)")
            self.logDeviceCommunication("DiaBox final totalEmitted=\(newGlucoses.count) countTimesWithoutData=\(self.countTimesWithoutData) willReport=\(self.countTimesWithoutData > 1 ? "noValidSensorData" : (newGlucoses.isEmpty ? "noData" : "newData"))", type: newGlucoses.isEmpty ? .error : .receive)

            self.latestPrediction = prediction?.first

            // must be inside this handler as setobservables "depend" on latestbackfill
            self.setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

            self.logger.debug("handleGoodReading returned with \(newGlucoses.count) entries")
            self.delegateQueue.async {
                var result: CGMReadingResult
                // If several readings from a valid and running sensor come out empty,
                // we have (with a large degree of confidence) a sensor that has been
                // ripped off the body
                if self.countTimesWithoutData > 1 {
                    result = .error(LibreError.noValidSensorData)
                } else {
                    result = newGlucoses.isEmpty ? .noData : .newData(newGlucoses)
                }
                self.cgmManagerDelegate?.cgmManager(self, hasNew: result)
            }
        }

    }
    private func readingToGlucose(_ data: SensorData) -> GlucoseArrayWithPrediction {
        let result = DiaBoxLibreParser.parseWithDiagnostics(data)
        var parsed = result.readings
        let diagnostics = result.diagnostics
        logger.debug("DiaBox parse result: framBytes=\(diagnostics.framByteCount, privacy: .public), didParse=\(diagnostics.didParse, privacy: .public), sensorTime=\(String(describing: diagnostics.sensorTimeInMinutes), privacy: .public), currentAccepted=\(diagnostics.currentAccepted, privacy: .public), currentRaw=\(String(describing: diagnostics.currentRawGlucose), privacy: .public), current=\(String(describing: diagnostics.currentGlucose), privacy: .public), currentRecord=\(String(describing: diagnostics.currentRecordNumber), privacy: .public), currentQuality=\(String(describing: diagnostics.currentDataQuality), privacy: .public), currentTime=\(String(describing: diagnostics.currentTimestamp), privacy: .public), rateOfChange=\(String(describing: diagnostics.currentRateOfChange), privacy: .public), history=\(diagnostics.historyCount, privacy: .public), rejectedHistoryQuality=\(diagnostics.rejectedHistoryQualityCount, privacy: .public), rejectedHistoryRange=\(diagnostics.rejectedHistoryRangeCount, privacy: .public), rejectedHistoryDate=\(diagnostics.rejectedHistoryDateCount, privacy: .public), backfillEnabled=\(UserDefaults.standard.mmBackfillFromHistory, privacy: .public)")
        logDeviceCommunication("DiaBox parse framBytes=\(diagnostics.framByteCount) didParse=\(diagnostics.didParse) sensorTime=\(String(describing: diagnostics.sensorTimeInMinutes)) currentAccepted=\(diagnostics.currentAccepted) currentRaw=\(String(describing: diagnostics.currentRawGlucose)) current=\(String(describing: diagnostics.currentGlucose)) currentRecord=\(String(describing: diagnostics.currentRecordNumber)) currentQuality=\(String(describing: diagnostics.currentDataQuality)) currentTime=\(String(describing: diagnostics.currentTimestamp)) rateOfChange=\(String(describing: diagnostics.currentRateOfChange)) history=\(diagnostics.historyCount) rejectedHistoryQuality=\(diagnostics.rejectedHistoryQualityCount) rejectedHistoryRange=\(diagnostics.rejectedHistoryRangeCount) rejectedHistoryDate=\(diagnostics.rejectedHistoryDateCount) backfillEnabled=\(UserDefaults.standard.mmBackfillFromHistory)", type: .receive)
        let currentRejectedReason: String
        if diagnostics.currentAccepted {
            currentRejectedReason = "none"
        } else if !diagnostics.didParse {
            currentRejectedReason = "parseFailed"
        } else if let sensorTime = diagnostics.sensorTimeInMinutes, sensorTime < 60 {
            currentRejectedReason = "sensorTimeBelow60"
        } else if let currentQuality = diagnostics.currentDataQuality, currentQuality != 0 {
            currentRejectedReason = "quality"
        } else if let currentRaw = diagnostics.currentRawGlucose, currentRaw < 39.0 || currentRaw > 501.0 {
            currentRejectedReason = "range"
        } else {
            currentRejectedReason = "missing"
        }
        let historyRawCount = diagnostics.historyCount + diagnostics.rejectedHistoryQualityCount + diagnostics.rejectedHistoryRangeCount + diagnostics.rejectedHistoryDateCount
        logDeviceCommunication("DiaBox current filter accepted=\(diagnostics.currentAccepted) reason=\(currentRejectedReason) raw=\(String(describing: diagnostics.currentRawGlucose)) quality=\(String(describing: diagnostics.currentDataQuality)) range=39...501", type: diagnostics.currentAccepted ? .receive : .error)
        logDeviceCommunication("DiaBox history filter raw=\(historyRawCount) accepted=\(diagnostics.historyCount) rejectedQuality=\(diagnostics.rejectedHistoryQualityCount) rejectedRange=\(diagnostics.rejectedHistoryRangeCount) rejectedDate=\(diagnostics.rejectedHistoryDateCount)", type: diagnostics.historyCount > 0 ? .receive : .error)
        if !UserDefaults.standard.mmBackfillFromHistory {
            logger.debug("DiaBox history disabled by mmBackfillFromHistory")
            logDeviceCommunication("DiaBox history disabled by mmBackfillFromHistory", type: .receive)
            parsed.historical = []
        }
        return parsed
    }

    public func handleGoodReading(data: SensorData?, _ callback: @escaping (LibreError?, GlucoseArrayWithPrediction?) -> Void) {
        // only care about the once per minute readings here, historical data will not be considered

        guard let data else {
            callback(.noSensorData, nil)
            return
        }
        
        callback(nil, readingToGlucose(data))
    }

    // will be called on utility queue
    public func libreDeviceStateChanged(_ state: BluetoothmanagerState) {
        DispatchQueue.main.async {
            self.transmitterInfoObservable.connectionState = self.proxy?.connectionStateString ?? "n/a"
            self.transmitterInfoObservable.transmitterType = self.proxy?.shortTransmitterName ?? "Unknown"
        }
        logDeviceCommunication("Sensor/Transmitter Device change state to: \(state.rawValue))", type: .connection)
        
        
        if case .Connected = state {
            lastConnected = Date()
        }
        
        return
    }
    
    public func libreDeviceLogMessage(payload: String, type: LoopKit.DeviceLogEntryType) {
        logDeviceCommunication(payload, type: type)
    }

    // will be called on utility queue
    public func libreDeviceReceivedMessage(_ txFlags: UInt8, payloadData: Data) {
        
        guard let packet = MiaoMiaoResponseState(rawValue: txFlags) else {
            // Incomplete package?
            // this would only happen if delegate is called manually with an unknown txFlags value
            // this was the case for readouts that were not yet complete
            logger.debug("Incomplete package or unknown response state")
            return
        }

        switch packet {
        case .newSensor:
            //we can't be sure of the activation datetime for the new sensor here
            logger.debug("New libresensor detected")
            NotificationHelper.sendSensorChangeNotificationIfNeeded()
        case .noSensor:
            logger.debug("No libresensor detected")
            NotificationHelper.sendSensorNotDetectedNotificationIfNeeded(noSensor: true)
        default:
            // we don't care about the rest!
            break
        }

        return
    }

    func tryPersistSensorData(with sensorData: SensorData) {
        guard UserDefaults.standard.shouldPersistSensorData else {
            return
        }

        // yeah, we really really need to persist any changes right away
        var data = UserDefaults.standard.queuedSensorData ?? LimitedQueue<SensorData>()
        data.enqueue(sensorData)
        UserDefaults.standard.queuedSensorData = data
    }
}
