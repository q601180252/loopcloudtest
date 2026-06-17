//
//  GlucoseAlgorithm.cpp
//  DiaBox
//
//  Created by yan on 2022/8/4.
//  Copyright © 2022 Johan Degraeve. All rights reserved.
//

#include "GlucoseAlgorithm.hpp"
#include "AlgorithmLet.c"

int historyDataLen;

int getHistoryDataLen() {
    return historyDataLen;
}

int readBits(uint8_t *buffer, int byteOffset, int bitOffset, int bitCount) {
    if (bitCount == 0) {
        return 0;
    }
    int res = 0;
    for (int i = 0; i < bitCount; i++) {
        int totalBitOffset = byteOffset * 8 + bitOffset + i;

        double byte = floor(totalBitOffset / 8);
        int bit = totalBitOffset % 8;
        if (totalBitOffset >= 0 && ((buffer[(int) byte] >> bit) & 0x1) == 1) {
            res = res | (1 << i);
        }
    }
    return res;
}

int *readCalibrationInfo(uint8_t *FRAMData) {

    int i1 = readBits(FRAMData, 2, 0, 3);
    int i2 = readBits(FRAMData, 2, 3, 0xa);
    int i3 = readBits(FRAMData, 0x150, 0, 8);
    int i4 = readBits(FRAMData, 0x150, 8, 0xe);
    int negativei3 = readBits(FRAMData, 0x150, 0x21, 1);
    if (negativei3 != 0) {
        i3 = -i3;
    }
    int i5 = readBits(FRAMData, 0x150, 0x28, 0xc) << 2;
    int i6 = readBits(FRAMData, 0x150, 0x34, 0xc) << 2;
    static int r[6];
    r[0] = i1;
    r[1] = i2;
    r[2] = i3;
    r[3] = i4;
    r[4] = i5;
    r[5] = i6;
    return r;
}

double glucoseValueFromRawNew(struct BLEGlucoseValue raw, int *calibrationInfo) {
    int x = 1000 + 71500;
    int y = 1000;

    double ca = 0.0009180023;
    double cb = 0.0001964561;
    double cc = 0.0000007061775;
    double cd = 0.00000005283566;
    double R = (((raw.temperature) * x) / (raw.temperatureAdjustment + calibrationInfo[5])) - y;
    double logR = log(R);
    double d = pow(logR, 3) * cd + pow(logR, 2) * cc + logR * cb + ca;
    double temperature = 1 / d - 273.15;
    double g1 = 65 * (raw.value - calibrationInfo[2]) / (calibrationInfo[3] - calibrationInfo[2]);
    double g2 = pow(1.045, 32.5 - temperature);
    double g3 = g1 * g2;
    double v1 = t1[calibrationInfo[1] - 1];
    double v2 = t2[calibrationInfo[1] - 1];

    double res = (g3 - v1) / v2;
    double v = round(res);
    return v;
}

double readGlucoseValue(uint8_t *data, int offset, int *valuess, int i) {
    int temperatureAdjustment = (readBits(data, offset, 0x26, 0x9) << 2);
    int negativeAdjustment = readBits(data, offset, 0x2f, 0x1) != 0;
    if (negativeAdjustment) {
        temperatureAdjustment = -temperatureAdjustment;
    }
    int value = readBits(data, offset, 0, 0xe);
    int temperature = readBits(data, offset, 0x1a, 0xc) << 2;

    BLEGlucoseValue raw = *new BLEGlucoseValue();
    raw.value = value;
    raw.temperature = temperature;
    raw.temperatureAdjustment = temperatureAdjustment;
//    int *valuess = readCalibrationInfo(data);
    double v = glucoseValueFromRawNew(raw, valuess);
    return v;
}

bool sub_78A14(uint8_t *buffer, int byteOffset, int a3) {
    int iOffset = a3 >> 3;
    int bUse = buffer[byteOffset + iOffset];
    int iTemp1 = a3 & 7;
    int iTemp2 = 1 << iTemp1;

    int rc = bUse & iTemp2;

    bool bRc = false;
    if (rc != 0) {
        bRc = true;
    }
    return bRc;
}

double glucoseValueFromRaw(struct BLEGlucoseValue raw, int *calibrationInfo) {

    double g1 = 65 * (raw.value - calibrationInfo[2]) / (calibrationInfo[3] - calibrationInfo[2]);
    double g2 = pow(1.045, 32.5 - raw.temperature);
    double g3 = g1 * g2;
    double v1 = t1[calibrationInfo[1] - 1];
    double v2 = t2[calibrationInfo[1] - 1];

    double res = (g3 - v1) / v2;
    double v = round(res);
    return v;
}


double glucoseTemperatureTempFromRaw(BLEGlucoseValue raw, int *calibrationInfo) {
    int x = 1000 + 71500;
    int y = 1000;
    if (raw.temperature == 128) {
        return 0.0;
    }
    double ca = 0.0009180023;
    double cb = 0.0001964561;
    double cc = 0.0000007061775;
    double cd = 0.00000005283566;
    double R = (((raw.temperature) * x) / (raw.temperatureAdjustment + calibrationInfo[5])) - y;
    double temperature = 0.0;
    if (R >= 0) {
        double logR = log(R);
        double d = pow(logR, 3) * cd + pow(logR, 2) * cc + logR * cb + ca;
        // 这一步很重要
        temperature = 1 / d - 273.15;
    }
    return temperature;
}

double getIdOffset(int i) {
    if (i == historyDataLen - 1) {
        return 94.00 + 75;
    } else if (i == historyDataLen - 2) {
        return 94.00 + 94 + 75;
    } else if (i == 1) {
        return 94.00 + 92 + 75;
    } else if (i == 0) {
        return 92.00 + 75;
    } else {
        return 94.00 * 2 + 92 + 75;
    }
}

double getTemperatureTempValue(int i, int count, double idSum,
                               double idPowSum, double valueSum, double idMultiplyValueSum,
                               BLEGlucoseValue *values) {
    double dm1 = idPowSum * count - idSum * idSum;
    double dm2 = idMultiplyValueSum * count - valueSum * idSum;
    // 算出 -1.392
    double ddiv1 = 0.0;
    if (abs(dm1) > 0.000001) {
        ddiv1 = dm2 / dm1;
    }
    values[i].t5ddiv1 = ddiv1;
    double d0 = 0.0;  // (idSum * ddiv1) / count;
    double d3 = 0.0;  // valueSum / count;
    double d2 = 0.0;  // d3 - d0;
    if (abs(count) > 0.000001) {
        d0 = (idSum * ddiv1) / count;
        d3 = valueSum / count;
        d2 = d3 - d0;
    }

    // 算出 145.020
    double res2 = d2 + ddiv1 * values[i].time;
    if (count == 1) {
        res2 = 0.0;
    }
    return res2;
}

int readGlucoseValueTemp1(uint8_t *data, int offset, int i, BLEGlucoseValue *values,
                          int *calibrationInfo) {
    int temperatureAdjustment = (readBits(data, offset, 0x26, 0x9) << 2);
    bool negativeAdjustment = readBits(data, offset, 0x2f, 0x1) != 0;
    if (negativeAdjustment) {
        temperatureAdjustment = -temperatureAdjustment;
    }
    int value = readBits(data, offset, 0, 0xe);
    int temperature = readBits(data, offset, 0x1a, 0xc) << 2;
    // itype
    int itype = readBits(data, offset, 0xe, 0xb);//14 11 2 3
    // 0x75072
    if (sub_78A14(data, offset, 0x19)) {
        values[i].type = itype & 0x1FF;
    } else {
        values[i].type = 0;
    }
    values[i].value = value;
    values[i].temperature = temperature;
    values[i].temperatureAdjustment = temperatureAdjustment;

    values[i].temperatureTemp1 = glucoseTemperatureTempFromRaw(values[i], calibrationInfo);
    values[i].dataQuality = 0;
    if (values[i].temperatureTemp1 < 0.0 || values[i].temperatureTemp1 > 50.0) {
        values[i].dataQuality |= 0x800;
    }

    if (values[i].temperatureTemp1 < 20.0) {
        values[i].dataQuality |= 0x4000;
    }

    if (values[i].temperatureTemp1 > 40.0) {
        values[i].dataQuality |= 0x2000;
    }

    // time < 45  不是你之前说的小于 60
    if (values[i].time < 45) {
        values[i].dataQuality |= 0x8000;
    }

    // 数据无效
    if (values[i].type == 0x20) {
        values[i].dataQuality |= 0x8000;
    }

    return values[i].dataQuality;
}

void readGlucoseValueTemp2(int i, BLEGlucoseValue *values, int *calibrationInfo) {

    double g1 =
            65 * (values[i].value - calibrationInfo[2]) / (calibrationInfo[3] - calibrationInfo[2]);
    double temperature = 0.0;
    if (i == historyDataLen - 1) {
        double valueSum = 0.0;
        int count = 0;

        if (values[i].type != 0x20 && values[i].dataQuality == 0) {
            valueSum += values[i].temperatureTemp1;
            count += 1;
        }

        if (values[i - 1].type != 0x20 && values[i - 1].dataQuality == 0) {
            valueSum += values[i - 1].temperatureTemp1;
            count += 1;
        }

        if (count <= 0) {
            temperature = values[i].temperatureTemp1;
        } else {
            temperature = valueSum / count;
        }

    } else {

        double valueSum = 0.0;
        int count = 0;
        // add fenfei 20211213   temperatureTemp1 不在 20.00 和 40.00 的 不参加 这一步运算
        // add fenfei 20211218   dataQuality不为0 的不参与运算。
        if (values[i + 1].type != 0x20 && values[i + 1].dataQuality == 0) {
            valueSum += values[i + 1].temperatureTemp1;
            count += 1;
        }

        if (values[i].type != 0x20 && values[i].dataQuality == 0) {
            valueSum += values[i].temperatureTemp1;
            count += 1;
        }

        // i=0 的时候不做这个运算
        if (i >= 1) {
            if (values[i - 1].type != 0x20 && values[i - 1].dataQuality == 0) {
                valueSum += values[i - 1].temperatureTemp1;
                count += 1;
            }
        }

        if (count <= 0) {
            // System.out.printf(" \n\n\n ????????? readGlucoseValueTemp2 Error ???????\n\n\n");
            // valueSum = bleGlucoseValues[i].temperatureTemp1;
            // add fenfei 20211218
            temperature = values[i].temperatureTemp1;
        } else {
            temperature = valueSum / count;
        }

    }

    double g2 = pow(1.045, 32.5 - temperature);
    double g3 = g1 * g2;
    double v1 = t1[calibrationInfo[1] - 1];
    double v2 = t2[calibrationInfo[1] - 1];
    double res = (g3 - v1) / v2;
    values[i].calibratinoInfoValue = res;
}

void readGlucoseValueTemp3Ex(int i, BLEGlucoseValue *values) {
    int count = 0;//次数
    double idSum = 0.0;   // 相邻的3个id相加
    double idPowSum = 0.0;       // 相邻的3个id的平方相加
    double valueSum = 0.0;      // 相邻的3个temperatureTemp2 相加
    double idMultiplyValueSum = 0.0;  // 相邻的3个id*temperatureTemp2 相加
    if (values[i].type != 0x20 &&
        values[i].dataQuality == 0 &&
        values[i].calibratinoInfoValue != -1  // add fenfei 20211223
            ) {
        idSum += values[i].time;
        count += 1;
        idPowSum += values[i].time * values[i].time;
        valueSum += values[i].calibratinoInfoValue;
        idMultiplyValueSum += values[i].time * values[i].calibratinoInfoValue;
    }
    if (i >= 1) {
        if (values[i - 1].type != 0x20 &&
            values[i - 1].dataQuality == 0 &&
            values[i - 1].calibratinoInfoValue != -1      // add fenfei 20211223
                ) {
            idSum += values[i - 1].time;
            count += 1;
            idPowSum += values[i - 1].time * values[i - 1].time;
            valueSum += values[i - 1].calibratinoInfoValue;
            idMultiplyValueSum +=
                    values[i - 1].time * values[i - 1].calibratinoInfoValue;
        }
    }
    if (i >= 2) {
        if (values[i - 2].type != 0x20 &&
            values[i - 2].dataQuality == 0 &&
            values[i - 2].calibratinoInfoValue != -1      // add fenfei 20211223
                ) {
            idSum += values[i - 2].time;
            count += 1;
            idPowSum += values[i - 2].time * values[i - 2].time;
            valueSum += values[i - 2].calibratinoInfoValue;
            idMultiplyValueSum +=
                    values[i - 2].time * values[i - 2].calibratinoInfoValue;
        }
    }
    values[i].countMath3 = count;
    double dm1 = idPowSum * count - idSum * idSum;
    double dm2 = idMultiplyValueSum * count - valueSum * idSum;
    double ddiv1 = 0.0;
    if (abs(dm1) > 0.000001) {
        ddiv1 = dm2 / dm1;
    }
    values[i].t3ddiv1 = ddiv1;
    values[i].value3 = getTemperatureTempValue(i, count, idSum, idPowSum, valueSum,
                                               idMultiplyValueSum, values);
}

void readGlucoseValueTemp4Ex(int i, BLEGlucoseValue *values) {

    int count = 0;
    double idSum = 0.0;    // 相邻的3个id相加    4410
    double idPowSum = 0.0;    //
    double valueSum = 0.0;
    double idMultiplyValueSum = 0.0;
    if (i < historyDataLen - 1) {
        if (values[i + 1].type != 0x20 &&
            values[i + 1].dataQuality == 0 &&
            values[i + 1].calibratinoInfoValue != -1) {
            idSum += values[i + 1].time;
            count += 1;
            idPowSum += values[i + 1].time * values[i + 1].time;
            valueSum += values[i + 1].calibratinoInfoValue;
            idMultiplyValueSum += values[i + 1].time * values[i + 1].calibratinoInfoValue;
        }
    }
    if (values[i].type != 0x20 &&
        values[i].dataQuality == 0 &&
        values[i].calibratinoInfoValue != -1) {
        idSum += values[i].time;
        count += 1;
        idPowSum += values[i].time * values[i].time;
        valueSum += values[i].calibratinoInfoValue;
        idMultiplyValueSum += values[i].time * values[i].calibratinoInfoValue;

    }
    if (i >= 1) {
        if (values[i - 1].type != 0x20 &&
            values[i - 1].dataQuality == 0 &&
            values[i - 1].calibratinoInfoValue != -1) {
            idSum += values[i - 1].time;
            count += 1;
            idPowSum += values[i - 1].time * values[i - 1].time;
            valueSum += values[i - 1].calibratinoInfoValue;
            idMultiplyValueSum += values[i - 1].time * values[i - 1].calibratinoInfoValue;
        }
    }
    values[i].countMath4 = count;
    values[i].value4 = getTemperatureTempValue(i, count, idSum, idPowSum, valueSum,
                                               idMultiplyValueSum, values);
}

void readGlucoseValueTemp5Ex(int i, BLEGlucoseValue *values) {

    int count = 0;
    double idSum = 0.0;
    double idPowSum = 0.0;
    double valueSum = 0.0;
    double idMultiplyValueSum = 0.0;
    if (i < historyDataLen - 2) {
        if (values[i + 2].type != 0x20 &&
            values[i + 2].dataQuality == 0 &&
            values[i + 2].calibratinoInfoValue != -1) {
            idSum += values[i + 2].time;
            count += 1;
            idPowSum += values[i + 2].time *
                        values[i + 2].time;
            valueSum += values[i + 2].calibratinoInfoValue;
            idMultiplyValueSum += values[i + 2].time *
                                  values[i + 2].calibratinoInfoValue;

        }
    }

    if (i < historyDataLen - 1) {
        if (values[i + 1].type != 0x20 &&
            values[i + 1].dataQuality == 0 &&
            values[i + 1].calibratinoInfoValue != -1) {
            idSum += values[i + 1].time;
            count += 1;
            idPowSum += values[i + 1].time *
                        values[i + 1].time;
            valueSum += values[i + 1].calibratinoInfoValue;
            idMultiplyValueSum += values[i + 1].time *
                                  values[i + 1].calibratinoInfoValue;

        }
    }

    if (values[i].type != 0x20 &&
        values[i].dataQuality == 0 &&
        values[i].calibratinoInfoValue != -1) {
        idSum += values[i].time;
        count += 1;
        idPowSum += values[i].time * values[i].time;
        valueSum += values[i].calibratinoInfoValue;
        idMultiplyValueSum +=
                values[i].time * values[i].calibratinoInfoValue;

    }
    values[i].countMath5 = count;
    double dm1 = idPowSum * count - idSum * idSum;
    double dm2 = idMultiplyValueSum * count - valueSum * idSum;
    double ddiv1 = 0.0;
    if (abs(dm1) > 0.000001) {
        ddiv1 = dm2 / dm1;
    }
    values[i].t5ddiv1 = ddiv1;
    // 算出 -2046.580
    double d0 = (idSum * ddiv1) / count;
    double d3 = valueSum / count;
    double d2 = d3 - d0;
    double res2 = d2 + ddiv1 * values[i].time;
    if (count == 1) {
        res2 = 0.0;
    }
    values[i].value5 = getTemperatureTempValue(i, count, idSum, idPowSum, valueSum,
                                               idMultiplyValueSum, values);
}

void readGlucoseValueTemp6Ex(int i, BLEGlucoseValue *values) {
//    double THRESHOLD = .0001;
    if (i == historyDataLen - 1) {
        //TODO 最新一个历史值 so都是返回0
        // 这个运算可能有问题，需要换个入参试试
        if (values[i].calibratinoInfoValue == -1) {
            values[i].value6 = values[i].value3;
        } else {
            values[i].value6 = (values[i].value3 + values[i].calibratinoInfoValue * 3) / 4;
        }
    } else {
        double weight3 = 1.0;
        double weight4 = 4.0;
        double weight5 = 1.0;
        double weight3_5 = 4.0;
        if (values[i].countMath3 < 3) {
            weight3 = 0.5;
            if (values[i].countMath3 < 2) {
                weight3 = 0.0;
            }
        }
        double value3 = values[i].value3 * weight3;
        if (values[i].countMath5 < 3) {
            weight5 = 0.5;
            if (values[i].countMath5 < 2) {
                weight5 = 0.0;
            }
        }
        double value5 = values[i].value5 * weight5;
        if (values[i].countMath4 < 3) {
            weight4 = 3.0;
            if (values[i].countMath4 < 2) {
                weight4 = 0.0;
            }
        }
        if (values[i].countMath3 < 2 ||
            values[i].countMath5 < 2) {
            weight3_5 = 0.0;
        } else {
            weight3_5 = 4.0;
        }
        double value4 = values[i].value4 * weight4;
        double value3_5 =
                (values[i].value5 + values[i].value3) * 0.5 *
                weight3_5;// 3 和5的平均值 *权重
        double valueSum = value3 + value4 + value5 + value3_5;
        double weightSum = weight3 + weight5 + weight4 + weight3_5;
        double res = valueSum / weightSum;
        values[i].value6 = res;
    }
}

double getiStep1A(int i, BLEGlucoseValue *bleGlucoseValues) {
    double d1 = 0.0;
    if (i < historyDataLen - 1) {
        // 0x0340e1
        d1 = bleGlucoseValues[i + 1].value6 - bleGlucoseValues[i].value6;
    }
    // 0x0340eb
    double d2 = d1 * 14.33;
    double d3 = 0.0;
    if (i >= 1) {
        d3 = bleGlucoseValues[i - 1].value6 - bleGlucoseValues[i].value6;
    }
    double d4 = d3 * 0.53;

    double d5 = d4 / 15.0;
    double d6 = d2 / -15;

    double d7 = d5 + d6;
    return d7;
}

double getiStep3(int i, double iStep3X, BLEGlucoseValue *bleGlucoseValues) {
    double iStep3 = 0.0;
    if (bleGlucoseValues[i].value6 > 95.00) {

        if (bleGlucoseValues[i].value6 > 160) {
            // 注意 这里 大于 500 还有个处理
            if (bleGlucoseValues[i].value6 > 500) {
                // 先不处理
            } else {
                iStep3 = ((bleGlucoseValues[i].value6 - 160.00) / -340.00 + 1) * iStep3X;
            }
        } else {
            iStep3 = iStep3X;
        }
    } else {
        iStep3 = ((bleGlucoseValues[i].value6 - 55.00) / 40.00) * iStep3X;
    }
    return iStep3;
}

double getiStep3Ex(double CurrV6, double iStep3X) {
    double iStep3 = 0.0;
    if (CurrV6 > 95.00) {
        if (CurrV6 > 160) {
            // 注意 这里 大于 500 还有个处理
            if (CurrV6 > 500) {
                // 先不处理
            } else {
                iStep3 = ((CurrV6 - 160.00) / -340.00 + 1) * iStep3X;
            }
        } else {
            iStep3 = iStep3X;
        }
    } else {
        if (CurrV6 > 55.0) {
            iStep3 = ((CurrV6 - 55.00) / 40.00) * iStep3X;
        }
//        iStep3 = ((CurrV6 - 55.00) / 40.00) * iStep3X;
    }
    return iStep3;
}

double getiStep4AEx(double CurrV6, double OneV6, double TwoV6) {
    double d1 = 0.0;
    d1 = OneV6 - CurrV6;
    double d2 = d1 * 14.77;
    double d6 = d2 / -15;
    double d18 = 0.0;
    d18 = TwoV6 - CurrV6;
    double d19 = d18 * -3.24;
    double d20 = d19 / -30.0;
    double d21 = d20 + d6;
    return d21;
}

double getiStep4A(int i, BLEGlucoseValue *values) {
    double d1 = 0.0;
    if (i < historyDataLen - 1) {
        d1 = values[i + 1].value6 - values[i].value6;
    }
    double d2 = d1 * 14.77;
    double d6 = d2 / -15;
    double d18 = 0.0;
    if (i < historyDataLen - 2) {
        d18 = values[i + 2].value6 - values[i].value6;
    }
    double d19 = d18 * -3.24;
    double d20 = d19 / -30.0;
    double d21 = d20 + d6;
    return d21;
}

double getiStep2A(int i, BLEGlucoseValue *bleGlucoseValues) {
    double d1 = 0.0;
    if (i >= 2) {
        d1 = bleGlucoseValues[i - 2].value6 - bleGlucoseValues[i].value6;
    }
    double d2 = d1 * -1.210;
    double d6 = d2 / 30.0;
    double d3 = 0.0;
    if (i >= 1) {
        d3 = bleGlucoseValues[i - 1].value6 - bleGlucoseValues[i].value6;
    }
    double d4 = d3 * 15.890;
    double d5 = d4 / 15.0;

    // 0x03411d
    double d7 = d5 + d6;
    return d7;
}

void readGlucoseValueTemp7Ex(int i, BLEGlucoseValue *bleGlucoseValues) {
    double dUse1 = bleGlucoseValues[i].value6;

    double dUse2 = 0.0;
//    double dUse3 = 0.0;
    double dUse4 = 0.0;
    double dUse5 = 0.0;
    double dDiv = getIdOffset(i);
    double res = 0.0;
    //如果血糖值值小月55 就不要计算
    if (bleGlucoseValues[i].value6 < 55) {
        res = bleGlucoseValues[i].value6;
    } else {
        double iStep1 = 0.0;
        iStep1 = getiStep1A(i, bleGlucoseValues);

        double iStep3 = 0.0;
        double iStep3X = 40;

        if (iStep1 < 0.0) {
            iStep3X = -20.00;
        }

        iStep3 = getiStep3(i, iStep3X, bleGlucoseValues);
        if (iStep1 < 0.0) {
            if (iStep3 > iStep1) {
                dUse2 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse2 = bleGlucoseValues[i].value6 + iStep1;
            }
        } else {
            if (iStep3 < iStep1) {
                dUse2 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse2 = bleGlucoseValues[i].value6 + iStep1;
            }
        }

        // add fenfei 20211223
        if (i >= (historyDataLen - 1) || i == 0) {
            // if (i >= 31 || i == 0) {
            dUse2 = 0.0;
        } else {
            // add fenfei 1203
            // if ( (bleGlucoseValues[i + 1].type == 0x20 || bleGlucoseValues[i - 1].type == 0x20) ){
            if (bleGlucoseValues[i + 1].dataQuality != 0.0 ||
                bleGlucoseValues[i - 1].dataQuality != 0.0) {
                dUse2 = 0.0;
                dDiv = dDiv - 94;       // 这个判断处理还有点问题，最好在  getIdOffset 函数里面就处理好
            }

            // end
        }

        bleGlucoseValues[i].value6x1 = dUse2;
        double iStep2 = 0.0;

        iStep2 = getiStep2A(i, bleGlucoseValues);

        iStep3X = 40;

        if (iStep2 < 0.0) {
            iStep3X = -20.00;
        }

        iStep3 = getiStep3(i, iStep3X, bleGlucoseValues);


        if (iStep2 < 0.0) {
            if (iStep3 > iStep2) {
                dUse4 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse4 = bleGlucoseValues[i].value6 + iStep2;
            }
        } else {
            if (iStep3 < iStep2) {
                dUse4 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse4 = bleGlucoseValues[i].value6 + iStep2;
            }
        }

        if (i <= 1) {
            dUse4 = 0.0;
        } else {
            // add fenfei 1203
            // if ( (bleGlucoseValues[i - 2].type == 0x20 || bleGlucoseValues[i - 1].type == 0x20) ){
            if (bleGlucoseValues[i - 2].dataQuality != 0.0 ||
                bleGlucoseValues[i - 1].dataQuality != 0.0) {
                dUse4 = 0.0;
                dDiv = dDiv - 94;       // 这个判断处理还有点问题，最好在  getIdOffset 函数里面就处理好
            }
            // end
        }

        double iStep4 = 0.0;
        iStep4 = getiStep4A(i, bleGlucoseValues);

        iStep3X = 40;

        if (iStep4 < 0.0) {
            iStep3X = -20.00;
        }

        iStep3 = getiStep3(i, iStep3X, bleGlucoseValues);

        if (iStep4 < 0.0) {
            if (iStep3 > iStep4) {
                dUse5 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse5 = bleGlucoseValues[i].value6 + iStep4;
            }

        } else {

            if (iStep3 < iStep4) {
                dUse5 = bleGlucoseValues[i].value6 + iStep3;
            } else {
                dUse5 = bleGlucoseValues[i].value6 + iStep4;
            }
        }

        // add fenfei 20211223
        if (i >= (historyDataLen - 2)) {
            dUse5 = 0.0;
        }
        double iD0 = dUse1; // d0
        double iD1 = dUse2; // d1
        double iD2 = dUse4;  // d2
        double iD0X = dUse5; // d0
        res = (iD0 * 75.00 + iD1 * 94.00 + iD2 * 94 + iD0X * 92) / dDiv;
    }
    bleGlucoseValues[i].value7 = res;
}

void timeOffset(int i, BLEGlucoseValue *values, bool bOffset) {
    if ((values[historyDataLen - 1].time - 0x3C) > 0xB04)//60   //2820
    {
        if (values[i].time < 0x3840) {
            values[i].timeOffset = 0.0;
        } else {
            if (values[i].time > 0x6AE0) {//27360
                double res = 12.00;
                // 这个判断没见过， 有了具体值的时候 看看
                values[i].timeOffset = res;
            } else {
                // 21E72
                int iUseTime = values[i].time - 0x3840;//14400
                double d1 = iUseTime * 12.00;
                double res = d1 / 12960.0;
                values[i].timeOffset = res;
            }
        }
    } else {
        double dC1 = 1.00222222;
        double dC2 = 1.00416667;
        double d1 = 0.0 - values[i].time;
        double d2 = pow(dC1, d1);
        double d3 = pow(dC2, d1);
        double res = (d2 - d3) * 80.00;
        if (values[i].calibratinoInfoValue < 120 && values[i].time < 1440 && bOffset) {
            // 0x231FE
            double resTemp = 0.3 * (values[i].time / -1440.0 + 1.0) *
                             (120.0 - values[i].calibratinoInfoValue);
            if (resTemp > 36.0) {
                // 这个判断没触发， 有数据了再来分析 0x23234
            }
            res = res + resTemp;
        }
        values[i].timeOffset = res;
    }
}

struct BLEGlucoseValue *readHistoricalValues(uint8_t *data) {
    int sensorTime = 256 * (data[317] & 0xFF) + (data[316] & 0xFF);
    int indexHistory = data[27] & 0xFF;
    static BLEGlucoseValue gBLEGlucoseValueArray[32];
    int *gCalibrationInfo = readCalibrationInfo(data);
    int historyIndex = (sensorTime / 15);
    if (historyIndex > 32) {
        historyIndex = 32;
    }
    historyDataLen = historyIndex;
    for (int index = 0; index < historyIndex; index++) {
        int i = indexHistory - index - 1;
        if (i < 0) i += 32;
        int address = i * 6 + 124;
        int time = abs((sensorTime - 3) / 15) * 15 - index * 15;
        gBLEGlucoseValueArray[index].time = time;
        readGlucoseValueTemp1(data, address, index, gBLEGlucoseValueArray, gCalibrationInfo);
    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp2(index, gBLEGlucoseValueArray, gCalibrationInfo);

    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp3Ex(index, gBLEGlucoseValueArray);
    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp4Ex(index, gBLEGlucoseValueArray);
    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp5Ex(index, gBLEGlucoseValueArray);
    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp6Ex(index, gBLEGlucoseValueArray);
    }
    for (int index = 0; index < historyIndex; index++) {
        readGlucoseValueTemp7Ex(index, gBLEGlucoseValueArray);
    }
    for (int index = 0; index < historyIndex; index++) {
        timeOffset(index, gBLEGlucoseValueArray, true);
    }

    for (int index = 0; index < historyIndex; index++) {
        int v1 = round(gBLEGlucoseValueArray[index].value7 + gBLEGlucoseValueArray[index].timeOffset);
        if (v1 < 40) {
            v1 = 39;
        }
        gBLEGlucoseValueArray[index].oopValue = v1;
    }
    return gBLEGlucoseValueArray;
}

bool gethasBeenRemoved(struct BLEGlucoseValue *glucoseHistoryArray, int histroyLen) {
    int Out14CalcArray[histroyLen];
    for (int i = 0; i < histroyLen; i++) {
        Out14CalcArray[i] = 0x7E;
    }
    // 第二步  把历史值第二轮计算出来的 值 temperatureTemp2  四舍五入  ，
    // 由于咱们之前算 历史值是 倒序， so里面其实是顺序，所以这里改成顺序。  其实 对这一步的算法， 顺序倒序无所谓
    for (int i = 0; i < histroyLen; i++) {
        int iTemp = (int) round(glucoseHistoryArray[31 - i].calibratinoInfoValue);
        if (iTemp < 120) {
            Out14CalcArray[i] = iTemp;
        }
    }


    // 第三步 开始 第一次比较
    int iCheck = 0x3CC0;   // 0x3CC0 / 5 = 3110
    int iSumOut14 = 0;
    for (int i = 0; i < histroyLen; i++) {
        int iTemp = 0x3F - Out14CalcArray[i];
        if (iTemp > 0) {
            iSumOut14 += iTemp;
            if (iSumOut14 * 5 > iCheck) {
                return true;
            }
        }

    }

    // 第四步 第三步没有 挑出来就再比较第四步， 如果跳出来了 就 不比第四步了
    iCheck = 0x1440;   // 0x1440 / 5 = 5148
    iSumOut14 = 0;
    for (int i = 0; i < histroyLen; i++) {
        int iTemp = 0x36 - Out14CalcArray[i];
        if (iTemp > 0) {
            iSumOut14 += iTemp;

            if (iSumOut14 * 5 > iCheck) {
                return true;
            }
        }

    }
    return false;
}

void readGlucoseValueTemp2Curr(int i, int iSize, BLEGlucoseValue *bleGlucoseValues,
                               int *calibrationInfo) {
    double temperature = 0.0;
    double dTemp = 0.0;
    int iDiv = 0;

    int iStepUse = i + 3;
    int iStepAdd = 0;
    if (i > 2) {
        iStepUse = 5;
        iStepAdd = i - 2;
    }


    // add fenfei 20210925 增加了一个 value != 0.0 判断
    int jUse = 0;
    while (jUse < iStepUse) {
        if (bleGlucoseValues[jUse + iStepAdd].type != 0x20 &&
            bleGlucoseValues[jUse + iStepAdd].value != 0.0) {
            dTemp += bleGlucoseValues[jUse + iStepAdd].value;
            iDiv += 1;
        }

        jUse += 1;

        if (jUse + iStepAdd >= iSize) {
            break;
        }
    }

    // add fenfei 2021-11-16
    if (iDiv == 0.0) {
        temperature = 0.0;
    } else {
        temperature = dTemp / iDiv;
    }


    double temperature2 = 0.0;
    double dTemp2 = 0.0;

    int iStepD2 = 7;
    if (i > 12) {
        iStepD2 = iSize - i + 3;
    } else if (i < 3) {
        iStepD2 = i + 4;
    }


    int iDiv2 = 0;

    int iStepD6 = i + 3;
    if (i > 11) {
        iStepD6 = iSize - 1;
    }


    // add fenfei 20210925 增加了一个 temperatureTemp1 != 0.0 判断
    int j = 0;
    while (j < iStepD2) {
        if (bleGlucoseValues[iStepD6].type != 0x20 &&
            bleGlucoseValues[iStepD6].temperatureTemp1 != 0.0) {
            dTemp2 += bleGlucoseValues[iStepD6].temperatureTemp1;
            iDiv2 += 1;
        }

        iStepD6 -= 1;
        j += 1;
    }

    // add fenfei 2021-11-16
    if (iDiv2 == 0.0) {
        temperature2 = 0.0;
    } else {
        temperature2 = dTemp2 / iDiv2;
    }


    double g2 = pow(1.045, 32.5 - temperature2);

    //  double g3 = (( dTemp / iDiv) - gCalibrationInfo.i3 ) * g2  / dTemp2;

    // add fenfei 2021-11-16
    double g1 = 0.0;
    if ((calibrationInfo[3] - calibrationInfo[2] != 0) && (iDiv != 0)) {
        g1 = 65 * ((dTemp / iDiv) - calibrationInfo[2]) / (calibrationInfo[3] - calibrationInfo[2]);

    }
    // end

    double g3 = g1 * g2;

    double v1 = t1[calibrationInfo[1] - 1];
    double v2 = t2[calibrationInfo[1] - 1];
    double res = (g3 - v1) / v2;

    // add fenfei 2021-11-16  这是猜测， 负值就 置为0
    if (res < 0) {
        bleGlucoseValues[i].calibratinoInfoValue = 0.0;
    } else {
        bleGlucoseValues[i].calibratinoInfoValue = res;
    }
    bleGlucoseValues[i].calibratinoInfoValue = res;
}

double getiStep2AEx(double CurrV6, double OneV6, double TwoV6, double tAUse, double tBUse) {
    double d1 = 0.0;
    d1 = OneV6 - CurrV6;
    // 0x27132  tBUse  tAUse 来历
    double d2 = d1 * tBUse; // 2.3340;   // 这两个常量是数组   0x400340da 使用和体现
    double d6 = d2 / -15.00;
    double d3 = 0.0;
    d3 = TwoV6 - CurrV6;
    double d4 = d3 * tAUse;  // -0.690;
    double d5 = d4 / -30;
    double d7 = d5 + d6;
    return d7;
}

int *getValueAndArrow(BLEGlucoseValue *glucoseValues, double dAdd1,
                      double dAdd2,
                      double dAdd3, double dAdd4,
                      double CurrV6, double OneV6, double TwoV6, int iTimeStep) {
    double iStep2 = 0.0;
    iStep2 = getiStep2AEx(CurrV6, OneV6, TwoV6, tA[iTimeStep], tB[iTimeStep]);
    double dSumAdd = glucoseValues[15].calibratinoInfoValue * 75.00;
    double dDivAdd = 75.00;
    bool bTrendArrow = true;
    if (glucoseValues[0].calibratinoInfoValue == 0 ||
        glucoseValues[9].calibratinoInfoValue == 0) {
        dAdd2 = 0;
        bTrendArrow = false;
    }
    if (glucoseValues[13].calibratinoInfoValue == 0.0 ||
        glucoseValues[8].calibratinoInfoValue == 0.0) {
        dAdd3 = 0;
        bTrendArrow = false;
    }
    if (glucoseValues[11].calibratinoInfoValue == 0.0 ||
        glucoseValues[3].calibratinoInfoValue == 0.0) {
        dAdd4 = 0;
        bTrendArrow = false;
    }
    if (dAdd2 != 0) {
        dSumAdd += dAdd2 * 91.00;
        dDivAdd += 91.00;
    }
    if (dAdd3 != 0) {
        dSumAdd += dAdd3 * 90.00;
        dDivAdd += 90.00;
    }
    if (dAdd4 != 0) {
        dSumAdd += dAdd4 * 91;
        dDivAdd += 91;
    }
    // 0x2B72A
    if (iStep2 > -5.0 && iStep2 < 5.5) {
        // 0x2f4f0
        dSumAdd += dAdd1 * tC[iTimeStep]; // 86.00;
        dDivAdd += tC[iTimeStep];   // 86.00;
    }
    double dCurr1 = dSumAdd / dDivAdd;


    // 把 1929 做下第八轮运算
    timeOffset(15, glucoseValues, false);
    double dCurr2 = dCurr1 + glucoseValues[15].timeOffset;
    int trendValue = (int) round(dCurr2);

    // add fenfei 20211227
    if (trendValue > 400) {
        trendValue = 401;
    }

    if (trendValue < 40) {
        trendValue = 39;
    }
    double dUse1;
    double dUse2;
    double dUse3;
    int trendArrow = 0;
    if (bTrendArrow) {
        // add fenfei 20211228
        if (glucoseValues[0].calibratinoInfoValue == 0 ||
            glucoseValues[9].calibratinoInfoValue == 0) {
            dAdd1 = 0.0;
        } else {
            dUse1 = (glucoseValues[9].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 1.02;
            dUse2 = (glucoseValues[0].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 0.217;
            dUse3 = dUse1 / -6.00 + dUse2 / -15.00;

            dAdd1 = dUse3;
        }

        if (glucoseValues[13].calibratinoInfoValue == 0 ||
            glucoseValues[8].calibratinoInfoValue == 0) {
            dAdd2 = 0.0;
        } else {
            dUse1 = (glucoseValues[13].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 0.169;
            dUse2 = (glucoseValues[8].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 1.054;
            dUse3 = dUse1 / -2.00 + dUse2 / -7.00;

            dAdd2 = dUse3;
        }

        if (glucoseValues[11].calibratinoInfoValue == 0 ||
            glucoseValues[3].calibratinoInfoValue == 0) {
            dAdd3 = 0.0;
        } else {
            dUse1 = (glucoseValues[11].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 0.585;
            dUse2 = (glucoseValues[3].calibratinoInfoValue -
                     glucoseValues[15].calibratinoInfoValue) * 0.634;
            dUse3 = dUse1 / -4.00 + dUse2 / -12.00;
            dAdd3 = dUse3;
        }

        // dSumAdd = dAdd1 * 91.00 + dAdd2 * 90.00 + dAdd3 * 91.00;
        // dDivAdd = 91.00 + 90.00 + 91.00;
        // add fenfei 20211229
        dSumAdd = 0.0;
        dDivAdd = 0.0;

        if (dAdd1 != 0.0) {
            dSumAdd += dAdd1 * 91.00;
            dDivAdd += 91.00;
        }

        if (dAdd2 != 0.0) {
            dSumAdd += dAdd2 * 90.0;
            dDivAdd += 90.0;
        }

        if (dAdd3 != 0.0) {
            dSumAdd += dAdd3 * 91.00;
            dDivAdd += 91.00;
        }

        if (iStep2 > -5.0 && iStep2 < 5.5) {
            // 0x2f4f0  2f49e
            dSumAdd += iStep2 * tC[iTimeStep]; // 86.00;
            dDivAdd += tC[iTimeStep];   // 86.00;
        }

        dCurr1 = dSumAdd / dDivAdd;

        if (dCurr1 < 2.0) {
            if (dCurr1 < 1.0) {
                if (dCurr1 > -2.0) {
                    if (dCurr1 > -1.0) {
                        trendArrow = 3;
                    } else {
                        trendArrow = 2;
                    }
                } else {
                    trendArrow = 1;
                }
            } else {
                trendArrow = 4;
            }
        } else {
            trendArrow = 5;
        }

        if (trendValue - 40 > 460) {
            trendArrow = 0;
        }
    } else {
        trendArrow = 0;
    }

    static int r[5];
    r[0] = trendValue;
    r[1] = trendArrow;
    r[2] = glucoseValues[15].time;
    r[3] = (int)(dCurr1 * 1000);
    r[4] = glucoseValues[15].dataQuality;
    return r;
}

int *gCalibrationInfo;

int *readTrendValue(uint8_t *data, struct BLEGlucoseValue *gBLEGlucoseValueArray) {
    int sensorTime = 256 * (data[317] & 0xFF) + (data[316] & 0xFF);
    int indexCurr = data[26] & 0xFF;
//    int timeIndex = ((sensorTime - indexCurr) / 16) * 16 + indexCurr;
    BLEGlucoseValue glucoseTrendArray[16];
    // 这几个值记录下来，后面算当前值的时候有用
    double CurrV6 = gBLEGlucoseValueArray[0].value6;
    double OneV6 = gBLEGlucoseValueArray[1].value6;
    double TwoV6 = gBLEGlucoseValueArray[2].value6;
    int iTimeEnd = gBLEGlucoseValueArray[0].time;
    int *gCalibrationInfo = readCalibrationInfo(data);
    int iCurr = indexCurr * 2 + indexCurr;
    iCurr = 0x1C + iCurr * 2;
    int iStepRead = (0x7C - iCurr) / 6;
    int dataQuality = 0;
    for (int index = 0; index < 16; index++) {
        int address = iCurr + index * 6;
        if (address > 0x76) {
            address = 0x1C + (index - iStepRead) * 6;
        }
//        int time = (sensorTime / 16) * 16 + indexCurr - 15 + index;
        int time = ((sensorTime - indexCurr) / 16) * 16 + indexCurr - 15 + index;
        glucoseTrendArray[index].time = time;
        dataQuality = readGlucoseValueTemp1(data, address, index, glucoseTrendArray,
                                            gCalibrationInfo);
//        if (dataQuality != 0) {
//            return dataQuality;
//        }
    }
    for (int index = 0; index < 16; index++) {
        readGlucoseValueTemp2Curr(index, 16, glucoseTrendArray, gCalibrationInfo);
    }

    int iTimeStep = glucoseTrendArray[15].time - iTimeEnd;
    if (iTimeStep > 14) {
        iTimeStep = 0;
    }
    double dUse1 = (TwoV6 - CurrV6) * tY[iTimeStep];  // -6.900;
    double dUse2 = (OneV6 - CurrV6) * tX[iTimeStep];  // 23.3400;
    double dUse3 = dUse1 / -30.00 + dUse2 / -15.00;
    // 这里和历史值的算法有些类似
    double iStep4 = 0.0;
    iStep4 = getiStep4AEx(CurrV6, OneV6, TwoV6);

    double iStep3X = 40;

    if (iStep4 < 0.0) {
        iStep3X = -20.00;
    }

    double iStep3Curr = getiStep3Ex(CurrV6, iStep3X);
    double dAdd1 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd1 = CurrV6 + iStep3Curr;
        } else {
            dAdd1 = CurrV6 + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd1 = CurrV6 + iStep3Curr;
        } else {
            dAdd1 = CurrV6 + dUse3;
        }
    }
    iStep3Curr = getiStep3Ex(glucoseTrendArray[15].calibratinoInfoValue, iStep3X);
    // end
    dUse1 = (glucoseTrendArray[9].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 10.20;
    dUse2 = (glucoseTrendArray[0].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 2.17;
    dUse3 = dUse1 / -6.00 + dUse2 / -15.00;
    double dAdd2 = 0.0;
    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd2 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd2 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd2 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd2 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    }


    dUse1 = (glucoseTrendArray[13].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 1.69;
    dUse2 = (glucoseTrendArray[8].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 10.54;
    dUse3 = dUse1 / -2.00 + dUse2 / -7.00;
    double dAdd3 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd3 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd3 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd3 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd3 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    }

    // double dAdd3 = gBLEGlucoseValueArray[15].calibratinoInfoValue + dUse3;

    dUse1 = (glucoseTrendArray[11].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 5.85;
    dUse2 = (glucoseTrendArray[3].calibratinoInfoValue -
             glucoseTrendArray[15].calibratinoInfoValue) * 6.34;
    dUse3 = dUse1 / -4.00 + dUse2 / -12.00;
    double dAdd4 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd4 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd4 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd4 = glucoseTrendArray[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd4 = glucoseTrendArray[15].calibratinoInfoValue + dUse3;
        }
    }
    historyDataLen = 16;
    int *values = getValueAndArrow(glucoseTrendArray, dAdd1, dAdd2, dAdd3, dAdd4, CurrV6, OneV6,
                                   TwoV6,
                                   iTimeStep);
    return values;
}

uint16_t op(uint16_t value, uint16_t l1, uint16_t l2) {
    uint16_t res = (value) >> 2;
    if ((value & 1) == 1) {
        res ^= l2;
    }
    if ((value & 2) == 2) {// If second last bit is 1
        res ^= l1;
    }
    return res;
}

uint16_t * processCrypto(uint16_t s1, uint16_t s2, uint16_t s3, uint16_t s4, uint16_t l1, uint16_t l2) {
    uint16_t r0 = op(s1, l1, l2) ^s4;
    uint16_t r1 = op(r0, l1, l2) ^s3;
    uint16_t r2 = op(r1, l1, l2) ^s2;
    uint16_t r3 = op(r2, l1, l2) ^s1;
    uint16_t r4 = op(r3, l1, l2);
    uint16_t r5 = op(r4 ^ r0, l1, l2);
    uint16_t r6 = op(r5 ^ r1, l1, l2);
    uint16_t r7 = op(r6 ^ r2, l1, l2);

    static uint16_t result[4];

    result[0] = (r0 ^ r4);
    result[1] = (r1 ^ r5);
    result[2] = (r2 ^ r6);
    result[3] = (r3 ^ r7);
    return result;
}

uint16_t word(uint8_t high, uint8_t low) {
    uint16_t v = (high << 8) + (low & 0xff);
    return v;
}

uint8_t * Libre1DecryptData(const uint8_t *sensorId, const uint8_t *sensorInfo, const uint8_t *FRAMData) {
    uint16_t l1 = 0xa0c5;
    uint16_t l2 = 0x6860;
    uint16_t l3 = 0x14c6;
    uint16_t l4 = 0x0000;

    static uint8_t result[43 * 8];
//    static char result[43 * 8];
    for (uint16_t i = 0; i < 43; i++) {
        int y = word(sensorInfo[5], sensorInfo[4]);
        if (i < 3 || i >= 40) {
            y = 0xcadc;
        }
        int s1 = 0;
        if (sensorInfo[0] == 0xE5) {
            s1 = (((word(sensorId[5], sensorId[4]) + y) + i) & 0xffff);
        } else {
            s1 = (((word(sensorId[5], sensorId[4]) + (word(sensorInfo[5], sensorInfo[4]) ^ 0x44)) +
                   i) & 0xffff);
        }

        uint16_t s2 = (word(sensorId[3], sensorId[2]) + l4);
        uint16_t s3 = ((word(sensorId[1], sensorId[0]) + (i << 1)));
        uint16_t s4 = ((0x241a ^ l3));
        uint16_t *key = processCrypto(s1, s2, s3, s4, l1, l2);
        result[i * 8 + 0] = (FRAMData[i * 8 + 0] ^ (key[3] & 0xff));
        result[i * 8 + 1] = (FRAMData[i * 8 + 1] ^ ((key[3] >> 8) & 0xff));
        result[i * 8 + 2] = (FRAMData[i * 8 + 2] ^ (key[2] & 0xff));
        result[i * 8 + 3] = (FRAMData[i * 8 + 3] ^ ((key[2] >> 8) & 0xff));
        result[i * 8 + 4] = (FRAMData[i * 8 + 4] ^ (key[1] & 0xff));
        result[i * 8 + 5] = (FRAMData[i * 8 + 5] ^ ((key[1] >> 8) & 0xff));
        result[i * 8 + 6] = (FRAMData[i * 8 + 6] ^ (key[0] & 0xff));
        result[i * 8 + 7] = (FRAMData[i * 8 + 7] ^ ((key[0] >> 8) & 0xff));
    }
    return result;
}

int readWearTime(uint8_t *data) {
    int wearTimeMinutes = word(data[41], data[40]);
    return wearTimeMinutes;
}

double readTrendValuesBleData(uint8_t *contentData, uint8_t *bleData) {
    int i = 0;
    int temperatureAdjustment = readBits(bleData, i * 4, 0x1a, 0x5) << 2;
    int value = readBits(bleData, i * 4, 0, 0xe);
    int temperature = readBits(bleData, i * 4, 0xe, 0xc) << 2;
    int negativeAdjustment = readBits(bleData, i * 4, 0x1f, 0x1);
    if (negativeAdjustment != 0) {
        temperatureAdjustment = -temperatureAdjustment;
    }
    BLEGlucoseValue raw = *new BLEGlucoseValue();
    raw.value = value;
    raw.temperature = temperature;
    raw.temperatureAdjustment = temperatureAdjustment;
    int *valuess = readCalibrationInfo(contentData);
    double v = glucoseValueFromRaw(raw, valuess);
    return v;
}

void readBlueToothGlucoseValueTemp1(uint8_t *data, int offset, int i, BLEGlucoseValue *bleBuf) {
    int value = readBits(data, offset, 0x0, 0xe);
    int temperature = readBits(data, offset, 0xe, 0xc) << 2;
    int temperatureAdjustment = readBits(data, offset, 0x1a, 0x5) << 2;

    BLEGlucoseValue bleGlucoseValue = *new BLEGlucoseValue();
    bleGlucoseValue.value = value;
    bleGlucoseValue.temperature = temperature;
    bleGlucoseValue.temperatureAdjustment = temperatureAdjustment;
    // add fenfei  0924
    // 感觉 蓝牙数据把 temperature 和 type合并了使用，  temperature 原始读出来是 0x20 代表 type是 0x20
    if (temperature == 128) {
        bleGlucoseValue.type = 0x20;
    } else {
        bleGlucoseValue.type = 0x00;
    }
    // end

    bleBuf[i].value = value;
    bleBuf[i].temperature = temperature;
    bleBuf[i].temperatureAdjustment = temperatureAdjustment;
    bleBuf[i].type = bleGlucoseValue.type;

    bleBuf[i].temperatureTemp1 = glucoseTemperatureTempFromRaw(bleGlucoseValue, gCalibrationInfo);
}

void readGlucoseValueTemp2(int i, BLEGlucoseValue *bleGlucoseValues) {
    double g1 =
            65 * (bleGlucoseValues[i].value - gCalibrationInfo[2]) /
            (gCalibrationInfo[3] - gCalibrationInfo[2]);
    double temperature = 0.0;
    if (i == historyDataLen - 1) {
        double dTemp =
                bleGlucoseValues[i].temperatureTemp1 + bleGlucoseValues[i - 1].temperatureTemp1;
        temperature = dTemp / 2.0;
    } else {

        double valueSum = 0.0;
        int count = 0;
        if (bleGlucoseValues[i + 1].type != 0x20) {
            valueSum += bleGlucoseValues[i + 1].temperatureTemp1;
            count += 1;
        }

        if (bleGlucoseValues[i].type != 0x20) {
            valueSum += bleGlucoseValues[i].temperatureTemp1;
            count += 1;
        }

        // i=0 的时候不做这个运算
        if (i >= 1) {
            if (bleGlucoseValues[i - 1].type != 0x20) {
                valueSum += bleGlucoseValues[i - 1].temperatureTemp1;
                count += 1;
            }
        }

        if (count <= 0) {
            // 这一步是我猜的
            valueSum = bleGlucoseValues[i].temperatureTemp1;
        } else {
            temperature = valueSum / count;
        }
    }

    double g2 = pow(1.045, 32.5 - temperature);
    double g3 = g1 * g2;
    double v1 = t1[gCalibrationInfo[1] - 1];
    double v2 = t2[gCalibrationInfo[1] - 1];
    double res = (g3 - v1) / v2;
    bleGlucoseValues[i].calibratinoInfoValue = res;
}


int *readBlueToothTrendValue(BLEGlucoseValue *bleBuf, double CurrV6, double OneV6, double TwoV6,
                             int iTimeEnd) {
    for (int index = 0; index < 16; index++) {
        readGlucoseValueTemp2Curr(index, 16, bleBuf, gCalibrationInfo);
    }

    //  133.634101 -> 134.713115
    int iTimeStep = bleBuf[15].time - iTimeEnd;
    double dUse1 = (TwoV6 - CurrV6) * tY[iTimeStep];  // -6.900;
    double dUse2 = (OneV6 - CurrV6) * tX[iTimeStep];  // 23.3400;
    double dUse3 = dUse1 / -30.00 + dUse2 / -15.00;
    // 这里和历史值的算法有些类似
    double iStep4 = 0.0;
    iStep4 = getiStep4AEx(CurrV6, OneV6, TwoV6);
    double iStep3X = 40;
    if (iStep4 < 0.0) {
        iStep3X = -20.00;
    }

    double iStep3Curr = getiStep3Ex(CurrV6, iStep3X);


    double dAdd1 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd1 = CurrV6 + iStep3Curr;
        } else {
            dAdd1 = CurrV6 + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd1 = CurrV6 + iStep3Curr;
        } else {
            dAdd1 = CurrV6 + dUse3;
        }
    }
    // end

    dUse1 = (bleBuf[9].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 10.20;
    dUse2 = (bleBuf[0].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 2.17;
    dUse3 = dUse1 / -6.00 + dUse2 / -15.00;

    double dAdd2 = 0.0;
    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd2 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd2 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd2 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd2 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    }
    iStep3Curr = getiStep3Ex(bleBuf[15].calibratinoInfoValue, iStep3X);
    dUse1 = (bleBuf[13].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 1.69;
    dUse2 = (bleBuf[8].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 10.54;
    dUse3 = dUse1 / -2.00 + dUse2 / -7.00;

    double dAdd3 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd3 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd3 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd3 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd3 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    }

    // double dAdd3 = gBLEGlucoseValueArray[15].calibratinoInfoValue + dUse3;

    dUse1 = (bleBuf[11].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 5.85;
    dUse2 = (bleBuf[3].calibratinoInfoValue - bleBuf[15].calibratinoInfoValue) * 6.34;
    dUse3 = dUse1 / -4.00 + dUse2 / -12.00;

    double dAdd4 = 0.0;

    if (iStep4 < 0.0) {
        if (iStep3Curr > dUse3) {
            dAdd4 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd4 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    } else {
        if (iStep3Curr < dUse3) {
            dAdd4 = bleBuf[15].calibratinoInfoValue + iStep3Curr;
        } else {
            dAdd4 = bleBuf[15].calibratinoInfoValue + dUse3;
        }
    }

    // double dAdd4 = gBLEGlucoseValueArray[15].calibratinoInfoValue + dUse3;

    // 144.589901  127.292436  127.539181 127.898526

    // sub_2EFC0     86.00 +
    double iStep2 = 0.0;
    iStep2 = getiStep2AEx(CurrV6, OneV6, TwoV6, tA[iTimeStep], tB[iTimeStep]);
    int *values = getValueAndArrow(bleBuf, dAdd1, dAdd2, dAdd3, dAdd4, CurrV6, OneV6, TwoV6,
                                   iTimeStep);
    return values;
}

int readBlueToothValue(uint8_t *patchinfo, uint8_t *data, uint8_t *bleData) {
    gCalibrationInfo = readCalibrationInfo(data);

    int iStepArray[] = {15, 12, 7, 6, 4, 2, 0};
    int indexCurr = readBits(patchinfo, 2, 4, 4);
    indexCurr = 6;
    int sensorTime = readBits(bleData, 0x28, 0, 0x10);
//    int value1 = readBits(bleData, 0x0, 4, 0x4);
//    int value2 = readBits(bleData, 0x0, 0, 0xe);

    int time = abs((sensorTime - 3) / 15) * 15;

    static BLEGlucoseValue BlueToothBLEGlucoseValueArray[10];
    for (int i = 0; i < 10; i++) {
        BlueToothBLEGlucoseValueArray[i] = *new BLEGlucoseValue();
    }


    static BLEGlucoseValue bleHistory[4];
    for (int i = 0; i < 4; i++) {
        bleHistory[i] = *new BLEGlucoseValue();
    }

    int iCurr = indexCurr * 4;
    int iStepRead = iCurr / 4 + 1;

    for (int index = 0; index < 10; index++) {
        int address = iCurr - index * 4;
        if (address < 0x0) {
            address = 0x24 - (index - iStepRead) * 4;
        }
        int timeTemp = 0;
        if (index < 7) {
            timeTemp = sensorTime - iStepArray[index];
        } else {
            // 历史值  3项，  间隔 15分钟
            timeTemp = time - (9 - index) * 15;
        }
        BlueToothBLEGlucoseValueArray[index].time = timeTemp;

        readBlueToothGlucoseValueTemp1(bleData, address, index, BlueToothBLEGlucoseValueArray);
    }

    for (int i = 0; i < 3; i++) {
        bleHistory[i].time = BlueToothBLEGlucoseValueArray[9 - i].time;
        bleHistory[i].type = BlueToothBLEGlucoseValueArray[9 - i].type;
        bleHistory[i].value = BlueToothBLEGlucoseValueArray[9 - i].value;
        bleHistory[i].temperature = BlueToothBLEGlucoseValueArray[9 - i].temperature;
        bleHistory[i].temperatureAdjustment = BlueToothBLEGlucoseValueArray[9 -
                                                                            i].temperatureAdjustment;
        bleHistory[i].temperatureTemp1 = BlueToothBLEGlucoseValueArray[9 - i].temperatureTemp1;
        // gBLEGlucoseValueArray[i].type = gBLEGlucoseValueArray[i+3].type;
    }


    int indexLen = 3;

    historyDataLen = indexLen;
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp2(index, bleHistory);
    }

    bleHistory[3].time = bleHistory[2].time - 15;
    bleHistory[3].type = 0;
    bleHistory[3].value = 0;
    bleHistory[3].temperature = 0;
    bleHistory[3].temperatureAdjustment = 0;

    bleHistory[3].temperatureTemp1 = 0;
    bleHistory[3].calibratinoInfoValue = -1;  // add fenfei 20211223  注意， 我这里故意把他置为 -1  为的是在第三、四、五轮这个值不参与运算

    indexLen = 4;
    historyDataLen = indexLen;

    if (showLog)
        LOGE(" -----------------  蓝牙值 第3轮  -----------------");
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp3Ex(index, bleHistory);
        if (showLog)
            LOGE("value3====%.6f======%d======%d\n", bleHistory[index].value3,
                 bleHistory[index].time,
                 index);
    }
    if (showLog)
        LOGE(" -----------------  蓝牙值 第4轮  -----------------");
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp4Ex(index, bleHistory);
    }
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp5Ex(index, bleHistory);
    }
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp6Ex(index, bleHistory);
    }
    for (int index = 0; index < indexLen; index++) {
        readGlucoseValueTemp7Ex(index, bleHistory);
    }
    if (showLog)
        LOGE(" -----------------  蓝牙值 第7轮  -----------------");
    for (int index = 0; index < indexLen; index++) {
        timeOffset(index, bleHistory, true);
    }
    if (showLog)
        LOGE(" -----------------  蓝牙值 第8轮  -----------------");
    for (int index = 0; index < indexLen; index++) {
        long v1 = round(bleHistory[index].value7 + bleHistory[index].timeOffset);
        if (v1 < 40) {
            v1 = 39;
        }

        bleHistory[index].oopValue = (int)v1;
        if (showLog) {
            LOGE("value6====%.6f====%.6f======%d======%d======%.6f", bleHistory[index].value6,
                 bleHistory[index].value7, bleHistory[index].time,
                 index, bleHistory[index].timeOffset);
        }

    }

    //  去计算蓝牙的当前值  数组的前 7项
    double CurrV6 = bleHistory[0].value6;
    double OneV6 = bleHistory[1].value6;
    double TwoV6 = bleHistory[2].value6;
    int iTimeEnd = bleHistory[0].time;

    // 重新创建一个蓝牙当前值数组， 也是 16项，
    if (showLog) {
        LOGE("蓝牙 CurrV6 = %.6f, OneV6= %.6f,  TwoV6= %.6f, iTimeEnd=%d\n", CurrV6, OneV6, TwoV6,
             iTimeEnd);
    }


    static BLEGlucoseValue BlueToothBLEGlucoseValueCurrArray[16];
    for (int i = 0; i < 16; i++) {
        BlueToothBLEGlucoseValueCurrArray[i] = *new BLEGlucoseValue();
        BlueToothBLEGlucoseValueCurrArray[i].time = sensorTime + i - 15;
    }
    // 把蓝牙之前读出来的七项， 按照time 匹配，存入到 BlueToothBLEGlucoseValueCurrArray 数组
    for (int i = 0; i < 16; i++) {
        for (int index = 0; index < 7; index++) {
            if (BlueToothBLEGlucoseValueCurrArray[i].time ==
                BlueToothBLEGlucoseValueArray[index].time) {
                BlueToothBLEGlucoseValueCurrArray[i].time = BlueToothBLEGlucoseValueArray[index].time;
                BlueToothBLEGlucoseValueCurrArray[i].type = BlueToothBLEGlucoseValueArray[index].type;
                BlueToothBLEGlucoseValueCurrArray[i].value = BlueToothBLEGlucoseValueArray[index].value;
                BlueToothBLEGlucoseValueCurrArray[i].temperature = BlueToothBLEGlucoseValueArray[index].temperature;
                BlueToothBLEGlucoseValueCurrArray[i].temperatureAdjustment = BlueToothBLEGlucoseValueArray[index].temperatureAdjustment;
                BlueToothBLEGlucoseValueCurrArray[i].temperatureTemp1 = BlueToothBLEGlucoseValueArray[index].temperatureTemp1;
                break;
            }
        }

    }

    return 0;
}

/**
 * Base64 解密
 * @param FRAMData 解密前 的字符串
 * @return 解密后的字符串
 */
uint8_t * Libre2DecryptData(const uint8_t *sensorId, const uint8_t *sensorInfo, const uint8_t *FRAMData) {
    return Libre1DecryptData(sensorId, sensorInfo, FRAMData);
}
