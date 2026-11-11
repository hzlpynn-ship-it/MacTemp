/*
 * smc_mt.h — MacTemp 传感器研究用只读 SMC 访问层
 * MacTemp 传感器研究工具 (research/ 专用，不参与 App 构建)
 *
 * 仅通过 IOKit 服务 AppleSMC 读取，不写 SMC、不需要 root。
 * 数值解码约定（实测校准，见 docs/SENSOR_MAP.md）：
 *   flt  : 4 字节 IEEE-754 float，**小端**（memcpy 直接读）
 *   sp78 / sp* : 2 字节有符号定点，大端
 *   fpe2 / fp* : 2 字节无符号定点，大端
 *   ui* / si8 / si16 : 大端整数
 *   ioft : 8 字节，语义未确认（见 docs），仅输出原始字节 + 候选解码
 */
#ifndef SMC_MT_H
#define SMC_MT_H

#include <stdint.h>

#define MT_SMC_TYPE_MAX 8

typedef struct {
    char   key[5];
    char   type[MT_SMC_TYPE_MAX]; /* 例如 "flt "、"sp78" */
    uint32_t dataSize;
    uint8_t  bytes[32];
} mt_smc_val;

int  mt_smc_open(void);
void mt_smc_close(void);
uint32_t mt_smc_key_count(void);
int  mt_smc_key_at(uint32_t index, char out_key[5]);
int  mt_smc_read(const char *key, mt_smc_val *out);

/** 解码为 double。返回 0 表示该类型不支持解码，*ok 置 0. */
double mt_smc_decode(const mt_smc_val *v, int *ok);
/** 类型是否属于"标准可解码数值类型" */
int mt_smc_type_decodable(const char *type);

#endif /* SMC_MT_H */
