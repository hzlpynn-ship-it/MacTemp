/*
 * proc_watch.c — MacTemp 传感器研究：按 1s 差分统计当前 CPU 占用来源（环境噪声诊断）
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用法: ./proc_watch <seconds>
 * 每秒打印：全部可见进程的 CPU% 之和 + 前 6 名进程，用于判断温度实验背景负载来源。
 */
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <time.h>
#include <unistd.h>

typedef struct {
    pid_t pid;
    char name[64];
    unsigned long long cpu_ns;
} ent;

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static int collect(ent **out) {
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (n <= 0) return 0;
    pid_t *pids = malloc(sizeof(pid_t) * (size_t)n);
    int cnt = proc_listpids(PROC_ALL_PIDS, 0, pids, n * (int)sizeof(pid_t)) / (int)sizeof(pid_t);
    ent *list = calloc((size_t)(cnt > 0 ? cnt : 1), sizeof(ent));
    int m = 0;
    for (int i = 0; i < cnt; i++) {
        struct proc_taskinfo ti;
        memset(&ti, 0, sizeof(ti));
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) != sizeof(ti)) continue;
        list[m].pid = pids[i];
        list[m].cpu_ns = ti.pti_total_user + ti.pti_total_system;
        if (proc_name(pids[i], list[m].name, sizeof(list[m].name)) <= 0)
            snprintf(list[m].name, sizeof(list[m].name), "?");
        m++;
    }
    free(pids);
    *out = list;
    return m;
}

static int cmp(const void *a, const void *b) {
    const ent *x = a, *y = b;
    if (x->cpu_ns < y->cpu_ns) return 1;
    if (x->cpu_ns > y->cpu_ns) return -1;
    return 0;
}

int main(int argc, char **argv) {
    double seconds = argc > 1 ? atof(argv[1]) : 10;
    ent *prev = NULL;
    int nprev = collect(&prev);
    double t0 = now_unix();
    while (now_unix() - t0 < seconds) {
        usleep(1000 * 1000);
        double t1 = now_unix();
        ent *cur = NULL;
        int ncur = collect(&cur);
        double dt = t1 - t0;
        t0 = t1;
        double total_pct = 0;
        for (int i = 0; i < ncur; i++) {
            unsigned long long old = 0;
            for (int j = 0; j < nprev; j++)
                if (prev[j].pid == cur[i].pid) { old = prev[j].cpu_ns; break; }
            if (cur[i].cpu_ns >= old) {
                double pct = 100.0 * (double)(cur[i].cpu_ns - old) / 1e9 / dt;
                cur[i].cpu_ns = (unsigned long long)(pct * 1e6); /* 临时存 pct*1e6 用于排序 */
                total_pct += pct;
            } else {
                cur[i].cpu_ns = 0;
            }
        }
        qsort(cur, (size_t)ncur, sizeof(ent), cmp);
        printf("t=%.2f visible_cpu_sum=%.0f%% procs=%d | ", t1, total_pct, ncur);
        for (int i = 0; i < ncur && i < 6; i++) {
            if (cur[i].cpu_ns < 50000) break; /* <5% */
            printf("%s(%d)=%.0f%% ", cur[i].name, cur[i].pid, (double)cur[i].cpu_ns / 1e6);
        }
        printf("\n");
        fflush(stdout);
        free(prev);
        prev = cur;
        nprev = ncur;
    }
    free(prev);
    return 0;
}
