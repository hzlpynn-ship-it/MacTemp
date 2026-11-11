#ifndef MT_SMC_BRIDGE_H
#define MT_SMC_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 一次 SMC 读取的结果。
typedef struct {
    char key[5];        ///< 4 字符 SMC 键名，NUL 结尾
    char type[5];       ///< 4 字符 SMC 数据类型，NUL 结尾
    uint32_t dataSize;  ///< 有效字节数（<= 32）
    uint8_t bytes[32];  ///< 原始载荷
} mt_smc_value;

/// 打开 AppleSMC 用户客户端。返回 0 成功；1 未找到服务；2 打开失败。
int mt_smc_open(void);

/// 关闭客户端（可重复调用）。
void mt_smc_close(void);

/// 是否已打开。
int mt_smc_is_open(void);

/// 读取 SMC 键总数（#KEY）。失败返回 0。
uint32_t mt_smc_key_count(void);

/// 读取第 index 个键的名字到 out_key[5]。返回 0 成功。
int mt_smc_key_at(uint32_t index, char out_key[5]);

/// 查询键的元数据。返回 0 成功。
int mt_smc_key_info(const char *key, uint32_t *out_size, uint32_t *out_type);

/// 已知 dataSize 时读取键内容（比 mt_smc_read_auto 少一次 IPC）。返回 0 成功。
int mt_smc_read(const char *key, uint32_t data_size, mt_smc_value *out_value);

/// 自动查询元数据并读取（扫描阶段使用）。返回 0 成功。
int mt_smc_read_auto(const char *key, mt_smc_value *out_value);

/// Swift 友好的简化读取接口（已知 dataSize，刷新阶段使用）。
/// out_bytes 至少 32 字节，未使用部分由 C 侧清零。返回 0 成功。
int mt_smc_read_simple(const char *key, uint32_t data_size, uint8_t out_bytes[32]);

/// Swift 友好的简化扫描接口：查询元数据并读取。
/// out_type 至少 5 字节（NUL 结尾），out_bytes 至少 32 字节。返回 0 成功。
int mt_smc_read_auto_simple(const char *key, uint32_t *out_size, char out_type[5],
                            uint8_t out_bytes[32]);

#ifdef __cplusplus
}
#endif

#endif
