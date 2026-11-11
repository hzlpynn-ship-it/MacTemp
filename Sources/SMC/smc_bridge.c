// MacTemp SMC 桥接层
// 通过 IOKit 与 AppleSMC 通信，读取 Apple Silicon 的 SMC 传感器键。
// 协议参考：AppleSMC 经典用户客户端（selector 2），与开源项目 smctemp 一致；
// 注意 Apple Silicon 上 flt 类型为小端浮点，由 Swift 侧的解码器处理。

#include "smc_bridge.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

#define MT_KERNEL_INDEX_SMC 2
#define MT_SMC_CMD_READ_BYTES 5
#define MT_SMC_CMD_READ_INDEX 8
#define MT_SMC_CMD_READ_KEYINFO 9

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} mt_smc_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} mt_smc_plimit_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} mt_smc_keyinfo_t;

typedef struct {
    uint32_t key;
    mt_smc_vers_t vers;
    mt_smc_plimit_t pLimitData;
    mt_smc_keyinfo_t keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} mt_smc_keydata_t;

// AppleSMC 用户客户端的结构体 ABI 固定为 80 字节，这个断言能提前发现布局漂移。
_Static_assert(sizeof(mt_smc_keydata_t) == 80, "unexpected SMCKeyData layout");

static io_connect_t g_conn = 0;
static int g_open = 0;

static uint32_t mt_key_to_u32(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) | (uint32_t)(uint8_t)key[3];
}

static int mt_smc_call(mt_smc_keydata_t *in, mt_smc_keydata_t *out) {
    size_t in_size = sizeof(mt_smc_keydata_t);
    size_t out_size = sizeof(mt_smc_keydata_t);
    kern_return_t kr =
        IOConnectCallStructMethod(g_conn, MT_KERNEL_INDEX_SMC, in, in_size, out, &out_size);
    return kr == KERN_SUCCESS ? 0 : 1;
}

int mt_smc_open(void) {
    if (g_open) return 0;
    io_service_t service =
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) return 2;
    g_open = 1;
    return 0;
}

void mt_smc_close(void) {
    if (g_open) {
        IOServiceClose(g_conn);
        g_conn = 0;
        g_open = 0;
    }
}

int mt_smc_is_open(void) { return g_open; }

int mt_smc_key_info(const char *key, uint32_t *out_size, uint32_t *out_type) {
    if (!g_open || !key) return 1;
    mt_smc_keydata_t in;
    mt_smc_keydata_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = mt_key_to_u32(key);
    in.data8 = MT_SMC_CMD_READ_KEYINFO;
    if (mt_smc_call(&in, &out) != 0) return 2;
    if (out.result != 0) return 3;
    if (out_size) *out_size = out.keyInfo.dataSize;
    if (out_type) *out_type = out.keyInfo.dataType;
    return 0;
}

int mt_smc_read(const char *key, uint32_t data_size, mt_smc_value *out_value) {
    if (!g_open || !key || !out_value) return 1;
    if (data_size > 32) return 2;
    memset(out_value, 0, sizeof(*out_value));

    mt_smc_keydata_t in;
    mt_smc_keydata_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = mt_key_to_u32(key);
    in.keyInfo.dataSize = data_size;
    in.data8 = MT_SMC_CMD_READ_BYTES;
    if (mt_smc_call(&in, &out) != 0) return 3;
    if (out.result != 0) return 4;

    memcpy(out_value->key, key, 4);
    out_value->key[4] = 0;
    out_value->dataSize = data_size;
    memcpy(out_value->bytes, out.bytes, sizeof(out_value->bytes));
    return 0;
}

int mt_smc_read_auto(const char *key, mt_smc_value *out_value) {
    if (!g_open || !key || !out_value) return 1;
    uint32_t data_size = 0;
    uint32_t data_type = 0;
    int rc = mt_smc_key_info(key, &data_size, &data_type);
    if (rc != 0) return rc;
    if (data_size > 32) return 5;

    memset(out_value, 0, sizeof(*out_value));
    memcpy(out_value->key, key, 4);
    out_value->key[4] = 0;
    out_value->type[0] = (char)((data_type >> 24) & 0xff);
    out_value->type[1] = (char)((data_type >> 16) & 0xff);
    out_value->type[2] = (char)((data_type >> 8) & 0xff);
    out_value->type[3] = (char)(data_type & 0xff);
    out_value->type[4] = 0;

    int rc2 = mt_smc_read(key, data_size, out_value);
    if (rc2 != 0) return rc2;
    out_value->type[0] = (char)((data_type >> 24) & 0xff);
    out_value->type[1] = (char)((data_type >> 16) & 0xff);
    out_value->type[2] = (char)((data_type >> 8) & 0xff);
    out_value->type[3] = (char)(data_type & 0xff);
    out_value->type[4] = 0;
    return 0;
}

int mt_smc_read_simple(const char *key, uint32_t data_size, uint8_t out_bytes[32]) {
    if (!g_open || !key || !out_bytes) return 1;
    if (data_size > 32) return 2;

    mt_smc_keydata_t in;
    mt_smc_keydata_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = mt_key_to_u32(key);
    in.keyInfo.dataSize = data_size;
    in.data8 = MT_SMC_CMD_READ_BYTES;
    if (mt_smc_call(&in, &out) != 0) return 3;
    if (out.result != 0) return 4;
    memcpy(out_bytes, out.bytes, 32);
    return 0;
}

int mt_smc_read_auto_simple(const char *key, uint32_t *out_size, char out_type[5],
                            uint8_t out_bytes[32]) {
    if (!g_open || !key || !out_bytes) return 1;
    uint32_t data_size = 0;
    uint32_t data_type = 0;
    int rc = mt_smc_key_info(key, &data_size, &data_type);
    if (rc != 0) return rc;
    if (data_size > 32) return 5;

    if (out_type) {
        out_type[0] = (char)((data_type >> 24) & 0xff);
        out_type[1] = (char)((data_type >> 16) & 0xff);
        out_type[2] = (char)((data_type >> 8) & 0xff);
        out_type[3] = (char)(data_type & 0xff);
        out_type[4] = 0;
    }
    if (out_size) *out_size = data_size;

    int rc2 = mt_smc_read_simple(key, data_size, out_bytes);
    return rc2;
}

uint32_t mt_smc_key_count(void) {
    mt_smc_value val;
    if (mt_smc_read_auto("#KEY", &val) != 0) return 0;
    if (val.dataSize < 4) return 0;
    return ((uint32_t)val.bytes[0] << 24) | ((uint32_t)val.bytes[1] << 16) |
           ((uint32_t)val.bytes[2] << 8) | (uint32_t)val.bytes[3];
}

int mt_smc_key_at(uint32_t index, char out_key[5]) {
    if (!g_open || !out_key) return 1;
    mt_smc_keydata_t in;
    mt_smc_keydata_t out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = MT_SMC_CMD_READ_INDEX;
    in.data32 = index;
    if (mt_smc_call(&in, &out) != 0) return 2;
    uint32_t k = out.key;
    out_key[0] = (char)((k >> 24) & 0xff);
    out_key[1] = (char)((k >> 16) & 0xff);
    out_key[2] = (char)((k >> 8) & 0xff);
    out_key[3] = (char)(k & 0xff);
    out_key[4] = 0;
    return 0;
}
