#import "DiaBoxGlucoseAlgorithm.h"
#import "GlucoseAlgorithm.hpp"

@implementation DiaBoxGlucoseAlgorithmValue

- (instancetype)initWithTimestamp:(NSDate *)timestamp
                           glucose:(double)glucose
                      recordNumber:(NSInteger)recordNumber
                         isHistory:(BOOL)isHistory
                       dataQuality:(NSInteger)dataQuality
                      rateOfChange:(double)rateOfChange {
    self = [super init];
    if (self) {
        _timestamp = timestamp;
        _glucose = glucose;
        _recordNumber = recordNumber;
        _isHistory = isHistory;
        _dataQuality = dataQuality;
        _rateOfChange = rateOfChange;
    }
    return self;
}

@end

@implementation DiaBoxGlucoseAlgorithmResult

- (instancetype)initWithCurrent:(DiaBoxGlucoseAlgorithmValue *)current
                        history:(NSArray<DiaBoxGlucoseAlgorithmValue *> *)history
            sensorTimeInMinutes:(NSInteger)sensorTimeInMinutes
     rejectedHistoryQualityCount:(NSInteger)rejectedHistoryQualityCount
       rejectedHistoryRangeCount:(NSInteger)rejectedHistoryRangeCount
        rejectedHistoryDateCount:(NSInteger)rejectedHistoryDateCount
               currentRawGlucose:(double)currentRawGlucose
             currentRecordNumber:(NSInteger)currentRecordNumber
              currentDataQuality:(NSInteger)currentDataQuality
             currentRateOfChange:(double)currentRateOfChange {
    self = [super init];
    if (self) {
        _current = current;
        _history = history;
        _sensorTimeInMinutes = sensorTimeInMinutes;
        _rejectedHistoryQualityCount = rejectedHistoryQualityCount;
        _rejectedHistoryRangeCount = rejectedHistoryRangeCount;
        _rejectedHistoryDateCount = rejectedHistoryDateCount;
        _currentRawGlucose = currentRawGlucose;
        _currentRecordNumber = currentRecordNumber;
        _currentDataQuality = currentDataQuality;
        _currentRateOfChange = currentRateOfChange;
    }
    return self;
}

@end

@implementation DiaBoxGlucoseAlgorithm

+ (BOOL)isValueInSensorRange:(double)value {
    return value >= 39.0 && value <= 501.0;
}

+ (nullable DiaBoxGlucoseAlgorithmResult *)parseFRAM:(NSData *)data readDate:(NSDate *)readDate {
    if (data.length != 344) {
        return nil;
    }

    NSMutableData *mutableData = [data mutableCopy];
    uint8_t *bytes = (uint8_t *)mutableData.mutableBytes;
    NSInteger sensorTime = 256 * (bytes[317] & 0xff) + (bytes[316] & 0xff);
    if (sensorTime < 60) {
        return [[DiaBoxGlucoseAlgorithmResult alloc] initWithCurrent:nil
                                                             history:@[]
                                                 sensorTimeInMinutes:sensorTime
                                          rejectedHistoryQualityCount:0
                                            rejectedHistoryRangeCount:0
                                             rejectedHistoryDateCount:0
                                                    currentRawGlucose:0.0
                                                  currentRecordNumber:0
                                                   currentDataQuality:0
                                                  currentRateOfChange:0.0];
    }

    struct BLEGlucoseValue *historyValues = readHistoricalValues(bytes);
    NSInteger historyLength = getHistoryDataLen();

    NSMutableArray<DiaBoxGlucoseAlgorithmValue *> *history = [NSMutableArray array];
    NSDate *minimumDate = [readDate dateByAddingTimeInterval:(NSTimeInterval)(-sensorTime * 60)];
    NSInteger rejectedHistoryQualityCount = 0;
    NSInteger rejectedHistoryRangeCount = 0;
    NSInteger rejectedHistoryDateCount = 0;

    for (NSInteger index = 0; index < historyLength; index++) {
        struct BLEGlucoseValue value = historyValues[index];
        if (value.dataQuality != 0) {
            rejectedHistoryQualityCount++;
            continue;
        }

        double glucose = value.oopValue;
        NSDate *timestamp = [readDate dateByAddingTimeInterval:(NSTimeInterval)((value.time - sensorTime) * 60)];
        if (![self isValueInSensorRange:glucose]) {
            rejectedHistoryRangeCount++;
            continue;
        }
        if ([timestamp compare:minimumDate] == NSOrderedAscending) {
            rejectedHistoryDateCount++;
            continue;
        }

        DiaBoxGlucoseAlgorithmValue *glucoseValue = [[DiaBoxGlucoseAlgorithmValue alloc] initWithTimestamp:timestamp
                                                                                                   glucose:glucose
                                                                                              recordNumber:value.time
                                                                                                 isHistory:YES
                                                                                               dataQuality:value.dataQuality
                                                                                              rateOfChange:0.0];
        [history addObject:glucoseValue];
    }

    int *trend = readTrendValue(bytes, historyValues);
    DiaBoxGlucoseAlgorithmValue *current = nil;
    double currentRawGlucose = trend[0];
    NSInteger currentRecordNumber = trend[2];
    NSInteger currentDataQuality = trend[4];
    double currentRateOfChange = ((double)trend[3]) / 1000.0;
    if (currentDataQuality == 0 && [self isValueInSensorRange:currentRawGlucose]) {
        current = [[DiaBoxGlucoseAlgorithmValue alloc] initWithTimestamp:readDate
                                                                 glucose:currentRawGlucose
                                                            recordNumber:currentRecordNumber
                                                               isHistory:NO
                                                             dataQuality:currentDataQuality
                                                            rateOfChange:currentRateOfChange];
    }

    return [[DiaBoxGlucoseAlgorithmResult alloc] initWithCurrent:current
                                                        history:history
                                            sensorTimeInMinutes:sensorTime
                                     rejectedHistoryQualityCount:rejectedHistoryQualityCount
                                       rejectedHistoryRangeCount:rejectedHistoryRangeCount
                                        rejectedHistoryDateCount:rejectedHistoryDateCount
                                               currentRawGlucose:currentRawGlucose
                                             currentRecordNumber:currentRecordNumber
                                              currentDataQuality:currentDataQuality
                                             currentRateOfChange:currentRateOfChange];
}

@end
