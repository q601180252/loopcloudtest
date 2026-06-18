#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIABOX_LIBRE_DIR="${DIABOX_LIBRE_DIR:-/Users/liyang/Documents/work/wunew/ios/diabox_ios/dixbox_ios-dev/Libre}"
CURRENT_DIR="$REPO_ROOT/LibreTransmitter/LibreSensor/DiaBoxAlgorithm"
FIXTURE="$DIABOX_LIBRE_DIR/nano76.txt"

if [[ ! -f "$FIXTURE" ]]; then
  echo "Missing DiaBox fixture: $FIXTURE" >&2
  exit 2
fi

HEX="$(sed -n 's/.*decodeData====//p' "$FIXTURE" | tail -1 | tr -d '[:space:]')"
if [[ ${#HEX} -ne 688 ]]; then
  echo "Expected 344-byte fixture, got $((${#HEX} / 2)) bytes" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/current_main.mm" <<'MM'
#import <Foundation/Foundation.h>
#import "DiaBoxGlucoseAlgorithm.h"

static NSData *DataFromHex(const char *hex) {
    NSMutableData *data = [NSMutableData data];
    size_t len = strlen(hex);
    for (size_t i = 0; i + 1 < len; i += 2) {
        unsigned int byte = 0;
        sscanf(hex + i, "%2x", &byte);
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSData *data = DataFromHex(argv[1]);
        NSDate *readDate = [NSDate dateWithTimeIntervalSince1970:1719540000];
        DiaBoxGlucoseAlgorithmResult *result = [DiaBoxGlucoseAlgorithm parseFRAM:data readDate:readDate];
        if (!result) { return 1; }

        printf("bytes=%lu sensorTime=%ld currentAccepted=%d currentRaw=%.0f current=%.0f record=%ld quality=%ld roc=%.3f history=%lu rejectedQuality=%ld rejectedRange=%ld rejectedDate=%ld\n",
               (unsigned long)data.length,
               (long)result.sensorTimeInMinutes,
               result.current != nil,
               result.currentRawGlucose,
               result.current ? result.current.glucose : -1,
               (long)result.currentRecordNumber,
               (long)result.currentDataQuality,
               result.currentRateOfChange,
               (unsigned long)result.history.count,
               (long)result.rejectedHistoryQualityCount,
               (long)result.rejectedHistoryRangeCount,
               (long)result.rejectedHistoryDateCount);

        for (DiaBoxGlucoseAlgorithmValue *value in result.history) {
            printf("H record=%ld glucose=%.0f quality=%ld offset=%.0f\n",
                   (long)value.recordNumber,
                   value.glucose,
                   (long)value.dataQuality,
                   [value.timestamp timeIntervalSinceDate:readDate] / 60.0);
        }
    }
    return 0;
}
MM

cat > "$TMP_DIR/source_main.mm" <<'MM'
#import <Foundation/Foundation.h>
#import "GlucoseAlgorithmOC.h"

static NSData *DataFromHex(const char *hex) {
    NSMutableData *data = [NSMutableData data];
    size_t len = strlen(hex);
    for (size_t i = 0; i + 1 < len; i += 2) {
        unsigned int byte = 0;
        sscanf(hex + i, "%2x", &byte);
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

static BOOL InRange(double value) {
    return value >= 39.0 && value <= 501.0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableData *data = [DataFromHex(argv[1]) mutableCopy];
        NSDate *readDate = [NSDate dateWithTimeIntervalSince1970:1719540000];
        uint8_t *bytes = (uint8_t *)data.mutableBytes;
        NSInteger sensorTime = 256 * (bytes[317] & 0xff) + (bytes[316] & 0xff);

        GlucoseAlgorithmOC *obj = [GlucoseAlgorithmOC new];
        struct BLEGlucoseValue *historyValues = [obj readHistoricalValues:bytes];
        NSInteger historyLength = [obj getHistoryDataLength];
        int *trend = [obj readTrendValue:bytes gBLEGlucoseValueArray:historyValues];

        double currentRawGlucose = trend[0];
        NSInteger currentRecordNumber = trend[2];
        NSInteger currentDataQuality = trend[4];
        double currentRateOfChange = ((double)trend[3]) / 1000.0;
        BOOL currentAccepted = currentDataQuality == 0 && InRange(currentRawGlucose);

        NSMutableArray<NSString *> *accepted = [NSMutableArray array];
        NSInteger rejectedQuality = 0;
        NSInteger rejectedRange = 0;
        NSInteger rejectedDate = 0;
        NSDate *minimumDate = [readDate dateByAddingTimeInterval:(NSTimeInterval)(-sensorTime * 60)];

        for (NSInteger index = 0; index < historyLength; index++) {
            struct BLEGlucoseValue value = historyValues[index];
            if (value.dataQuality != 0) {
                rejectedQuality++;
                continue;
            }

            double glucose = value.oopValue;
            NSDate *timestamp = [readDate dateByAddingTimeInterval:(NSTimeInterval)((value.time - sensorTime) * 60)];
            if (!InRange(glucose)) {
                rejectedRange++;
                continue;
            }
            if ([timestamp compare:minimumDate] == NSOrderedAscending) {
                rejectedDate++;
                continue;
            }

            [accepted addObject:[NSString stringWithFormat:@"H record=%d glucose=%.0f quality=%d offset=%.0f",
                                                               value.time,
                                                               glucose,
                                                               value.dataQuality,
                                                               [timestamp timeIntervalSinceDate:readDate] / 60.0]];
        }

        printf("bytes=%lu sensorTime=%ld currentAccepted=%d currentRaw=%.0f current=%.0f record=%ld quality=%ld roc=%.3f history=%lu rejectedQuality=%ld rejectedRange=%ld rejectedDate=%ld\n",
               (unsigned long)data.length,
               (long)sensorTime,
               currentAccepted,
               currentRawGlucose,
               currentAccepted ? currentRawGlucose : -1,
               (long)currentRecordNumber,
               (long)currentDataQuality,
               currentRateOfChange,
               (unsigned long)accepted.count,
               (long)rejectedQuality,
               (long)rejectedRange,
               (long)rejectedDate);

        for (NSString *line in accepted) {
            printf("%s\n", line.UTF8String);
        }
    }
    return 0;
}
MM

clang++ -std=c++17 -fobjc-arc -framework Foundation \
  -I"$CURRENT_DIR" \
  "$CURRENT_DIR/DiaBoxGlucoseAlgorithm.mm" \
  "$CURRENT_DIR/GlucoseAlgorithm.cpp" \
  "$TMP_DIR/current_main.mm" \
  -o "$TMP_DIR/current_parser"

clang++ -std=c++17 -fobjc-arc -framework Foundation \
  -I"$DIABOX_LIBRE_DIR" \
  "$DIABOX_LIBRE_DIR/GlucoseAlgorithmOC.mm" \
  "$DIABOX_LIBRE_DIR/GlucoseAlgorithm.cpp" \
  "$DIABOX_LIBRE_DIR/LibrePro.cpp" \
  "$TMP_DIR/source_main.mm" \
  -o "$TMP_DIR/source_parser"

"$TMP_DIR/current_parser" "$HEX" > "$TMP_DIR/current.out"
"$TMP_DIR/source_parser" "$HEX" > "$TMP_DIR/source.out"

diff -u "$TMP_DIR/source.out" "$TMP_DIR/current.out"
sed -n '1,40p' "$TMP_DIR/current.out"
echo "DiaBox parser comparison with strict quality filtering passed"
