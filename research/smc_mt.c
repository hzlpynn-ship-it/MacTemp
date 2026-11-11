/*
 * smc_mt.c — MacTemp 传感器研究用只读 SMC 访问层（实现）
 * MacTemp 传感器研究工具
 */
#include "smc_mt.h"

#include <IOKit/IOKitLib.h>
#include <math.h>
#include <string.h>
#include <strings.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} smc_vers_t;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} smc_plimit_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} smc_keyinfo_t;

typedef struct {
    uint32_t key;
    smc_vers_t vers;
    smc_plimit_t pLimitData;
    smc_keyinfo_t keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} smc_keydata_t;

static io_connect_t g_conn = 0;
static int g_open = 0;

static int smc_call(int index, smc_keydata_t *in, smc_keydata_t *out) {
    size_t in_size = sizeof(smc_keydata_t);
    size_t out_size = sizeof(smc_keydata_t);
    kern_return_t kr = IOConnectCallStructMethod(g_conn, (uint32_t)index, in, in_size, out, &out_size);
    return kr == KERN_SUCCESS ? 0 : 1;
}

int mt_smc_open(void) {
    if (g_open) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
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

static uint32_t key_to_u32(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) |
           ((uint32_t)(uint8_t)key[2] << 8) | (uint32_t)(uint8_t)key[3];
}

int mt_smc_read(const char *key, mt_smc_val *out_value) {
    if (!g_open || !key || strlen(key) < 4) return 1;
    memset(out_value, 0, sizeof(*out_value));

    smc_keydata_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));

    uint32_t k = key_to_u32(key);
    in.key = k;
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(KERNEL_INDEX_SMC, &in, &out) != 0) return 2;
    if (out.result != 0) return 3;

    uint32_t data_size = out.keyInfo.dataSize;
    uint32_t data_type = out.keyInfo.dataType;
    if (data_size > 32) return 4;

    out_value->dataSize = data_size;
    out_value->type[0] = (char)((data_type >> 24) & 0xff);
    out_value->type[1] = (char)((data_type >> 16) & 0xff);
    out_value->type[2] = (char)((data_type >> 8) & 0xff);
    out_value->type[3] = (char)(data_type & 0xff);
    out_value->type[4] = 0;
    memcpy(out_value->key, key, 4);
    out_value->key[4] = 0;

    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = k;
    in.keyInfo.dataSize = data_size;
    in.data8 = SMC_CMD_READ_BYTES;
    if (smc_call(KERNEL_INDEX_SMC, &in, &out) != 0) return 5;
    if (out.result != 0) return 6;

    memcpy(out_value->bytes, out.bytes, data_size);
    return 0;
}

uint32_t mt_smc_key_count(void) {
    mt_smc_val val;
    if (mt_smc_read("#KEY", &val) != 0) return 0;
    if (val.dataSize != 4) return 0;
    return ((uint32_t)val.bytes[0] << 24) | ((uint32_t)val.bytes[1] << 16) |
           ((uint32_t)val.bytes[2] << 8) | (uint32_t)val.bytes[3];
}

int mt_smc_key_at(uint32_t index, char out_key[5]) {
    if (!g_open) return 1;
    smc_keydata_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    if (smc_call(KERNEL_INDEX_SMC, &in, &out) != 0) return 2;
    uint32_t k = out.key;
    out_key[0] = (char)((k >> 24) & 0xff);
    out_key[1] = (char)((k >> 16) & 0xff);
    out_key[2] = (char)((k >> 8) & 0xff);
    out_key[3] = (char)(k & 0xff);
    out_key[4] = 0;
    return 0;
}

/* ---- 解码 ---- */

static int type_is(const char *t, const char *want) { return strncmp(t, want, 4) == 0; }

int mt_smc_type_decodable(const char *type) {
    static const char *types[] = {"flt ", "sp78", "fpe2", "fp88", "fp79", "fp6a", "fp5b", "fp4c",
                                  "fp1f", "sp96", "sp87", "sp69", "sp5a", "sp4b", "sp3c", "sp1e",
                                  "ui8 ", "ui16", "ui32", "ui64", "si8 ", "si16", "si32", "flag", NULL};
    for (int i = 0; types[i]; i++)
        if (type_is(type, types[i])) return 1;
    return 0;
}

static double be16_u(const uint8_t *b) { return (double)(((uint16_t)b[0] << 8) | b[1]); }
static double be16_s(const uint8_t *b) { return (double)(int16_t)(((uint16_t)b[0] << 8) | b[1]); }
static double be32_s(const uint8_t *b) {
    return (double)(int32_t)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
}

double mt_smc_decode(const mt_smc_val *v, int *ok) {
    const uint8_t *b = v->bytes;
    uint32_t n = v->dataSize;
    *ok = 1;

    if (type_is(v->type, "flt ") && n >= 4) {
        /* 关键结论：本机 flt 为小端 IEEE-754 float（与 smctemp memcpy 一致） */
        float f;
        memcpy(&f, b, sizeof(f));
        return (double)f;
    }
    if (type_is(v->type, "sp78") && n >= 2) return be16_s(b) / 256.0;
    if (type_is(v->type, "sp96") && n >= 2) return be16_s(b) / 64.0;
    if (type_is(v->type, "sp87") && n >= 2) return be16_s(b) / 128.0;
    if (type_is(v->type, "sp69") && n >= 2) return be16_s(b) / 512.0;
    if (type_is(v->type, "sp5a") && n >= 2) return be16_s(b) / 1024.0;
    if (type_is(v->type, "sp4b") && n >= 2) return be16_s(b) / 2048.0;
    if (type_is(v->type, "sp3c") && n >= 2) return be16_s(b) / 4096.0;
    if (type_is(v->type, "sp1e") && n >= 2) return be16_s(b) / 16384.0;
    if (type_is(v->type, "fpe2") && n >= 2) return be16_u(b) / 4.0;
    if (type_is(v->type, "fp88") && n >= 2) return be16_u(b) / 256.0;
    if (type_is(v->type, "fp79") && n >= 2) return be16_u(b) / 512.0;
    if (type_is(v->type, "fp6a") && n >= 2) return be16_u(b) / 1024.0;
    if (type_is(v->type, "fp5b") && n >= 2) return be16_u(b) / 2048.0;
    if (type_is(v->type, "fp4c") && n >= 2) return be16_u(b) / 4096.0;
    if (type_is(v->type, "fp1f") && n >= 2) return be16_u(b) / 32768.0;
    if (type_is(v->type, "ui8 ") && n >= 1) return (double)b[0];
    if (type_is(v->type, "ui16") && n >= 2) return be16_u(b);
    if (type_is(v->type, "ui32") && n >= 4) return (double)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3]);
    if (type_is(v->type, "ui64") && n >= 8) {
        double d = 0;
        for (int i = 0; i < 8; i++) d = d * 256.0 + b[i];
        return d;
    }
    if (type_is(v->type, "si8 ") && n >= 1) return (double)(int8_t)b[0];
    if (type_is(v->type, "si16") && n >= 2) return be16_s(b);
    if (type_is(v->type, "si32") && n >= 4) return be32_s(b);
    if (type_is(v->type, "flag") && n >= 1) return (double)b[0];

    *ok = 0;
    return 0.0;
}

double mt_smc_decode_candidate_ioft(const mt_smc_val *v);
/* ioft 候选解码：8 字节，低 4 字节为小端值，尝试 /65536 定点 (见 docs 不确定性说明) */
double mt_smc_decode_candidate_ioft(const mt_smc_val *v) {
    if (v->dataSize < 4) return 0.0;
    uint64_t lo = (uint64_t)v->bytes[0] | ((uint64_t)v->bytes[1] << 8) | ((uint64_t)v->bytes[2] << 16) |
                  ((uint64_t)v->bytes[3] << 24);
    /* 若高 4 字节为 FF FF FF FF 则按有符号扩展 */
    uint64_t hi = (uint64_t)v->bytes[4] | ((uint64_t)v->bytes[5] << 8) | ((uint64_t)v->bytes[6] << 16) |
                  ((uint64_t)v->bytes[7] << 24);
    int64_t full = (int64_t)(hi << 32 | lo);
    (void)full;
    return (double)((int64_t)(int32_t)lo) / 65536.0;
}
