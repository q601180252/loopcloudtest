//
//  GlucoseAlgorithm.hpp
//  DiaBox
//
//  Created by yan on 2022/8/4.
//  Copyright © 2022 Johan Degraeve. All rights reserved.
//

#ifndef GlucoseAlgorithm_hpp
#define GlucoseAlgorithm_hpp

#include <stdio.h>
#include <math.h>
#include "AlgorithmDefine.h"

int glucoseLength(struct BLEGlucoseValue * value);
int intLength(int * value);

int getHistoryDataLen();
/// 读历史值
/// @param data 344
struct BLEGlucoseValue *readHistoricalValues(uint8_t *data);

/// 读当前值
/// @param data 344
/// @param gBLEGlucoseValueArray 历史值, readHistoricalValues 的返回值
int *readTrendValue(uint8_t *data, struct BLEGlucoseValue *gBLEGlucoseValueArray);

/// 暂未用到
/// @param glucoseHistoryArray  历史值, readHistoricalValues 的返回值
/// @param histroyLen histroyLen
bool gethasBeenRemoved(struct BLEGlucoseValue *glucoseHistoryArray, int histroyLen);

int readBits(uint8_t *buffer, int byteOffset, int bitOffset, int bitCount);
int *readCalibrationInfo(uint8_t *FRAMData);
double readGlucoseValue(uint8_t *data, int offset, int *valuess, int i);

#endif /* GlucoseAlgorithm_hpp */
