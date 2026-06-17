#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DiaBoxGlucoseAlgorithmValue : NSObject

@property (nonatomic, readonly) NSDate *timestamp;
@property (nonatomic, readonly) double glucose;
@property (nonatomic, readonly) NSInteger recordNumber;
@property (nonatomic, readonly) BOOL isHistory;
@property (nonatomic, readonly) NSInteger dataQuality;
@property (nonatomic, readonly) double rateOfChange;

- (instancetype)initWithTimestamp:(NSDate *)timestamp
                           glucose:(double)glucose
                      recordNumber:(NSInteger)recordNumber
                         isHistory:(BOOL)isHistory
                       dataQuality:(NSInteger)dataQuality
                      rateOfChange:(double)rateOfChange NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface DiaBoxGlucoseAlgorithmResult : NSObject

@property (nonatomic, readonly, nullable) DiaBoxGlucoseAlgorithmValue *current;
@property (nonatomic, readonly) NSArray<DiaBoxGlucoseAlgorithmValue *> *history;
@property (nonatomic, readonly) NSInteger sensorTimeInMinutes;
@property (nonatomic, readonly) NSInteger rejectedHistoryQualityCount;
@property (nonatomic, readonly) NSInteger rejectedHistoryRangeCount;
@property (nonatomic, readonly) NSInteger rejectedHistoryDateCount;
@property (nonatomic, readonly) double currentRawGlucose;
@property (nonatomic, readonly) NSInteger currentRecordNumber;
@property (nonatomic, readonly) NSInteger currentDataQuality;
@property (nonatomic, readonly) double currentRateOfChange;

- (instancetype)initWithCurrent:(nullable DiaBoxGlucoseAlgorithmValue *)current
                        history:(NSArray<DiaBoxGlucoseAlgorithmValue *> *)history
            sensorTimeInMinutes:(NSInteger)sensorTimeInMinutes
     rejectedHistoryQualityCount:(NSInteger)rejectedHistoryQualityCount
       rejectedHistoryRangeCount:(NSInteger)rejectedHistoryRangeCount
        rejectedHistoryDateCount:(NSInteger)rejectedHistoryDateCount
               currentRawGlucose:(double)currentRawGlucose
             currentRecordNumber:(NSInteger)currentRecordNumber
              currentDataQuality:(NSInteger)currentDataQuality
             currentRateOfChange:(double)currentRateOfChange NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface DiaBoxGlucoseAlgorithm : NSObject

+ (nullable DiaBoxGlucoseAlgorithmResult *)parseFRAM:(NSData *)data readDate:(NSDate *)readDate;
+ (BOOL)isValueInSensorRange:(double)value;

@end

NS_ASSUME_NONNULL_END
