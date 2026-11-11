/*
 * cpu_load.c — MacTemp 传感器研究：按 QoS 只压性能核 / 只压能效核
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用法: ./cpu_load <p|e> <threads> <seconds>
 *   p: QoS_CLASS_USER_INTERACTIVE（调度到 P 性能核）
 *   e: QOS_CLASS_BACKGROUND       （调度到 E 能效核）
 * 结束后进程自行退出，不残留。
 */
#include <pthread.h>
#include <pthread/qos.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static atomic_int g_stop = 0;
static atomic_long g_iters = 0;
static qos_class_t g_qos = QOS_CLASS_USER_INTERACTIVE;

static void *worker(void *arg) {
    /* 在线程内部再次设置 QoS，双保险 */
    pthread_set_qos_class_self_np(g_qos, 0);
    volatile double x = 1.0 + (double)(long)arg * 0.001;
    long it = 0;
    while (!atomic_load_explicit(&g_stop, memory_order_relaxed)) {
        for (int i = 0; i < 200000; i++) {
            x = x * 1.0000001192092896 + 1.0e-7;
            if (x > 1e9) x = 1.0;
        }
        it++;
    }
    atomic_fetch_add(&g_iters, it);
    return NULL;
}

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <p|e> <threads> <seconds>\n", argv[0]);
        return 2;
    }
    const char *mode = argv[1];
    int threads = atoi(argv[2]);
    double seconds = atof(argv[3]);
    if (threads < 1 || threads > 64 || seconds <= 0) return 2;

    if (strcmp(mode, "p") == 0) {
        g_qos = QOS_CLASS_USER_INTERACTIVE;
    } else if (strcmp(mode, "e") == 0) {
        g_qos = QOS_CLASS_BACKGROUND;
    } else {
        fprintf(stderr, "mode must be p or e\n");
        return 2;
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_set_qos_class_np(&attr, g_qos, 0);

    pthread_t *tids = calloc((size_t)threads, sizeof(pthread_t));
    for (int i = 0; i < threads; i++) {
        if (pthread_create(&tids[i], &attr, worker, (void *)(long)i) != 0) {
            fprintf(stderr, "pthread_create %d failed\n", i);
            return 1;
        }
    }
    pthread_attr_destroy(&attr);

    fprintf(stderr, "[cpu_load] mode=%s threads=%d duration=%.1fs start=%.3f\n", mode, threads, seconds, now_unix());
    fflush(stderr);
    usleep((useconds_t)(seconds * 1e6));
    atomic_store(&g_stop, 1);
    for (int i = 0; i < threads; i++) pthread_join(tids[i], NULL);
    free(tids);
    fprintf(stderr, "[cpu_load] done end=%.3f iters=%ld\n", now_unix(), atomic_load(&g_iters));
    return 0;
}
