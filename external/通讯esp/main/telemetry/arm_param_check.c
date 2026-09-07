/* 临时布局校验(验证后可删): RunParamDef 必须 270 字节且 BMS 扩展组偏移正确 */
#include "arm_param.h"
#include <stddef.h>
#include <assert.h>

int arm_param_check(void) {
    RunParamDef r = {0};
    /* 原有字段偏移不变(前176字节布局未动) */
    _Static_assert(offsetof(RunParamDef, Eop_dischrTotal) == 172, "legacy layout");
    /* BMS 扩展组锚点 */
    _Static_assert(offsetof(RunParamDef, BmsOnline) == 176, "bms ext start");
    _Static_assert(offsetof(RunParamDef, BmsCellTempMax) == 200, "temps");
    _Static_assert(offsetof(RunParamDef, BmsTotalChgCap) == 230, "u32 caps");
    _Static_assert(offsetof(RunParamDef, BmsCellVolt) == 238, "cells");
    _Static_assert(sizeof(RunParamDef) == 270, "total size");
    (void)r;
    return 0;
}
