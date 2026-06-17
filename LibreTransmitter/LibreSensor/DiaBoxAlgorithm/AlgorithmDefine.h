//
//  AlgorithmDefine.h
//  DiaBox
//
//  Created by yan on 2022/8/4.
//  Copyright © 2022 Johan Degraeve. All rights reserved.
//

#ifndef AlgorithmDefine_h
#define AlgorithmDefine_h

#define LOGE(...)  printf(__VA_ARGS__)

struct BLEGlucoseValue {
    double temperatureAdjustment;
    double temperature;
    double value;
    int type;
    int value2;
    double temperatureTemp1;
    double calibratinoInfoValue;
    double value3;
    double t3ddiv1;
    int countMath3;
    double value4;
    int countMath4;
    double value5;
    double t5ddiv1;
    int countMath5;
    double value6;
    double value6x1;
    double value7;
    double timeOffset;
    int time;
    int oopValue;
    int dataQuality;
};

const static int showLog = 1;

#endif /* AlgorithmDefine_h */
