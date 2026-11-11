/*
 * cpu_watch.c — MacTemp 传感器研究：每秒记录每逻辑核占用率，用于验证 QoS 负载是否
 * 真的只落在 P 核（前 4 个逻辑核）或 E 核（后 6 个逻辑核）。
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用法: ./cpu_watch <seconds> <interval_ms> <out.csv>
 * 输出 CSV: t_unix,ncpu,total,cpu0,cpu1,...  （占用率 0..100）
 */
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static int read_ticks(unsigned long long **out, natural_t *n_out) {
    natural_t ncpu = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_cnt = 0;
    if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &info_cnt) != KERN_SUCCESS)
        return -1;
    unsigned long long *ticks = malloc(sizeof(unsigned long long) * ncpu * 4);
    processor_cpu_load_info_t load = (processor_cpu_load_info_t)info;
    for (natural_t i = 0; i < ncpu; i++) {
        ticks[i * 4 + 0] = load[i].cpu_ticks[CPU_STATE_USER];
        ticks[i * 4 + 1] = load[i].cpu_ticks[CPU_STATE_SYSTEM];
        ticks[i * 4 + 2] = load[i].cpu_ticks[CPU_STATE_IDLE];
        ticks[i * 4 + 3] = load[i].cpu_ticks[CPU_STATE_NICE];
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, info_cnt * sizeof(integer_t));
    *out = ticks;
    *n_out = ncpu;
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <seconds> <interval_ms> <out.csv>\n", argv[0]);
        return 2;
    }
    double seconds = atof(argv[1]);
    int interval_ms = atoi(argv[2]);
    FILE *f = fopen(argv[3], "w");
    if (!f) { perror("fopen"); return 1; }

    unsigned long long *prev = NULL;
    natural_t nprev = 0;
    if (read_ticks(&prev, &nprev) != 0) { fprintf(stderr, "host_processor_info failed\n"); return 1; }

    fprintf(f, "t_unix,ncpu,total");
    for (natural_t i = 0; i < nprev; i++) fprintf(f, ",cpu%u", i);
    fprintf(f, "\n");

    double t_end = now_unix() + seconds;
    while (now_unix() < t_end) {
        usleep((useconds_t)(interval_ms * 1000));
        unsigned long long *cur = NULL;
        natural_t ncur = 0;
        if (read_ticks(&cur, &ncur) != 0) break;
        double t = now_unix();
        double *usage = calloc(ncur, sizeof(double));
        double tot_busy = 0, tot_all = 0;
        for (natural_t i = 0; i < ncur; i++) {
            unsigned long long busy = (cur[i * 4 + 0] - prev[i * 4 + 0]) + (cur[i * 4 + 1] - prev[i * 4 + 1]) +
                                      (cur[i * 4 + 3] - prev[i * 4 + 3]);
            unsigned long long idle = cur[i * 4 + 2] - prev[i * 4 + 2];
            unsigned long long all = busy + idle;
            usage[i] = all ? 100.0 * (double)busy / (double)all : 0.0;
            tot_busy += (double)busy;
            tot_all += (double)all;
        }
        fprintf(f, "%.3f,%u,%.1f", t, ncur, tot_all ? 100.0 * tot_busy / tot_all : 0.0);
        for (natural_t i = 0; i < ncur; i++) fprintf(f, ",%.1f", usage[i]);
        fprintf(f, "\n");
        fflush(f);
        free(usage);
        free(prev);
        prev = cur;
        nprev = ncur;
    }
    free(prev);
    fclose(f);
    return 0;
}
