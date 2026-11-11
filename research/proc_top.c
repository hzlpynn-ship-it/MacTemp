/*
 * proc_top.c — MacTemp 传感器研究：环境噪声诊断用的极简 top
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用于在温度实验前确认"背景负载"来自哪些进程（不参与 App 构建）。
 * 用法: ./proc_top [topN]
 * 依赖 libproc 的 PROC_PIDTASKINFO（同用户进程可用，无需 root）。
 */
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <unistd.h>

typedef struct {
    pid_t pid;
    char name[64];
    unsigned long long cpu_ns;
    unsigned long long mem_bytes;
} ent;

static int cmp_cpu(const void *a, const void *b) {
    const ent *x = a, *y = b;
    if (x->cpu_ns < y->cpu_ns) return 1;
    if (x->cpu_ns > y->cpu_ns) return -1;
    return 0;
}

int main(int argc, char **argv) {
    int topn = argc > 1 ? atoi(argv[1]) : 10;
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (n <= 0) { fprintf(stderr, "proc_listpids failed\n"); return 1; }
    pid_t *pids = malloc(sizeof(pid_t) * (size_t)n);
    int cnt = proc_listpids(PROC_ALL_PIDS, 0, pids, n * (int)sizeof(pid_t)) / (int)sizeof(pid_t);
    if (cnt <= 0) { fprintf(stderr, "no pids\n"); return 1; }

    ent *list = calloc((size_t)cnt, sizeof(ent));
    int m = 0;
    for (int i = 0; i < cnt; i++) {
        if (pids[i] <= 0) continue;
        struct proc_taskinfo ti;
        memset(&ti, 0, sizeof(ti));
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &ti, sizeof(ti)) != sizeof(ti)) continue;
        list[m].pid = pids[i];
        list[m].cpu_ns = ti.pti_total_user + ti.pti_total_system;
        list[m].mem_bytes = ti.pti_resident_size;
        if (proc_name(pids[i], list[m].name, sizeof(list[m].name)) <= 0)
            snprintf(list[m].name, sizeof(list[m].name), "?");
        m++;
    }
    qsort(list, (size_t)m, sizeof(ent), cmp_cpu);
    printf("%-8s %-12s %-30s %s\n", "PID", "CPU_NS_TOTAL", "COMMAND", "RSS_MB");
    for (int i = 0; i < m && i < topn; i++) {
        printf("%-8d %-12llu %-30.30s %.1f\n", list[i].pid, list[i].cpu_ns, list[i].name,
               (double)list[i].mem_bytes / (1024.0 * 1024.0));
    }
    free(list);
    free(pids);
    return 0;
}
