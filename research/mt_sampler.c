/*
 * mt_sampler.c — MacTemp 传感器研究：全 T* 键采样器
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用法:
 *   ./mt_sampler list  <out.csv>                     枚举并打印全部 T* 键（含类型/当前值/原始字节）
 *   ./mt_sampler sample <seconds> <interval_ms> <out.csv>
 *                                                    长表 CSV: t_unix,key,value 每 interval 采样一次
 *   额外键（PSTR 等功耗键）也会采样，便于验证整机功耗与温度的关系。
 */
#include "smc_mt.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* 除 T* 之外额外关心的键（功耗/环境） */
static const char *kExtraKeys[] = {"PSTR", "PPBR", "PDTR", "PC0C", "PCAM", "PCTR", "PCPC",
                                   "PMTR", "PC3C", "PG0C", "PG0R", "PB0R", "VD0R", NULL};

static int is_temp_key(const char *k) { return k[0] == 'T'; }

static void print_hex(const uint8_t *b, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) printf("%02X", b[i]);
}

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static int cmd_list(const char *out_path) {
    FILE *f = fopen(out_path, "w");
    if (!f) { perror("fopen"); return 1; }
    fprintf(f, "key,type,size,value,decodable,hex\n");

    uint32_t count = mt_smc_key_count();
    printf("SMC key count: %u\n", count);
    int n_temp = 0, n_extra = 0;
    for (uint32_t i = 0; i < count; i++) {
        char key[5] = {0};
        if (mt_smc_key_at(i, key) != 0) continue;
        int wanted = is_temp_key(key);
        for (int j = 0; kExtraKeys[j]; j++) if (strcmp(key, kExtraKeys[j]) == 0) wanted = 1;
        if (!wanted) continue;
        mt_smc_val v;
        if (mt_smc_read(key, &v) != 0) continue;
        int ok = 0;
        double val = mt_smc_decode(&v, &ok);
        char hex[65] = {0};
        for (uint32_t b = 0; b < v.dataSize && b < 32; b++) sprintf(hex + b * 2, "%02X", v.bytes[b]);
        fprintf(f, "%s,%s,%u,%.6f,%d,%s\n", key, v.type, v.dataSize, ok ? val : 0.0, ok, hex);
        if (is_temp_key(key)) {
            n_temp++;
            printf("%-4s %-5s size=%u ok=%d value=%10.3f hex=%s\n", key, v.type, v.dataSize, ok, ok ? val : 0.0, hex);
        } else {
            n_extra++;
        }
    }
    printf("\nT* keys: %d, extra keys: %d\n", n_temp, n_extra);
    fclose(f);
    return 0;
}

static int cmd_sample(double seconds, int interval_ms, const char *out_path) {
    FILE *f = fopen(out_path, "w");
    if (!f) { perror("fopen"); return 1; }
    fprintf(f, "t_unix,key,value\n");

    uint32_t count = mt_smc_key_count();
    /* 先枚举出要采样的键并缓存 keyInfo（通过首次读取） */
    char (*keys)[5] = malloc(sizeof(char[5]) * (count + 16));
    if (!keys) return 1;
    int n = 0;
    for (uint32_t i = 0; i < count; i++) {
        char key[5] = {0};
        if (mt_smc_key_at(i, key) != 0) continue;
        int wanted = is_temp_key(key);
        for (int j = 0; kExtraKeys[j]; j++) if (strcmp(key, kExtraKeys[j]) == 0) wanted = 1;
        if (!wanted) continue;
        memcpy(keys[n], key, 5);
        n++;
    }
    printf("sampling %d keys every %d ms for %.1f s -> %s\n", n, interval_ms, seconds, out_path);
    fflush(stdout);

    double t_end = now_unix() + seconds;
    long samples = 0;
    while (now_unix() < t_end) {
        double t = now_unix();
        for (int i = 0; i < n; i++) {
            mt_smc_val v;
            if (mt_smc_read(keys[i], &v) != 0) continue;
            if (strcmp(v.type, "ioft") == 0) {
                /* ioft 不参与主流分析，直接跳过（在 list 中可见） */
                continue;
            }
            int ok = 0;
            double val = mt_smc_decode(&v, &ok);
            if (!ok) continue;
            fprintf(f, "%.3f,%s,%.6f\n", t, keys[i], val);
        }
        samples++;
        double dt = (double)interval_ms / 1000.0 - (now_unix() - t);
        if (dt > 0) usleep((useconds_t)(dt * 1e6));
    }
    fclose(f);
    free(keys);
    printf("done: %ld samples\n", samples);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s list <out.csv> | sample <seconds> <interval_ms> <out.csv>\n", argv[0]);
        return 2;
    }
    if (mt_smc_open() != 0) {
        fprintf(stderr, "failed to open AppleSMC (no root needed; check IOKit access)\n");
        return 1;
    }
    int rc = 2;
    if (strcmp(argv[1], "list") == 0 && argc >= 3) {
        rc = cmd_list(argv[2]);
    } else if (strcmp(argv[1], "sample") == 0 && argc >= 5) {
        rc = cmd_sample(atof(argv[2]), atoi(argv[3]), argv[4]);
    } else {
        fprintf(stderr, "bad args\n");
    }
    mt_smc_close();
    return rc;
}
