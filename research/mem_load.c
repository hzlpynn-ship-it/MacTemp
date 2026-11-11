/*
 * mem_load.c — MacTemp 传感器研究：内存带宽/容量负载（用于判断内存温度传感器）
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 用法: ./mem_load <GB> <seconds> [threads]
 * 申请匿名内存并按 cache line 跨步读写，制造 LPDDR 活动。结束后 munmap 退出。
 */
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static atomic_int g_stop = 0;
static uint8_t *g_buf = NULL;
static size_t g_len = 0;
static int g_threads = 2;

static void *worker(void *arg) {
    long id = (long)arg;
    size_t stride = 64;
    /* 每个线程从不同偏移开始，交错扫描整个缓冲区 */
    size_t n = g_len / stride;
    size_t chunk = n / (size_t)g_threads;
    size_t start = chunk * (size_t)id;
    size_t end = (id == g_threads - 1) ? n : start + chunk;
    volatile uint64_t sink = 0;
    while (!atomic_load_explicit(&g_stop, memory_order_relaxed)) {
        for (size_t i = start; i < end; i++) {
            uint8_t *p = g_buf + i * stride;
            sink += p[0] + p[32];
            p[0] = (uint8_t)(sink & 0xff);
        }
    }
    return (void *)(uintptr_t)(sink & 0xffff);
}

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    double gb = argc > 1 ? atof(argv[1]) : 4.0;
    double seconds = argc > 2 ? atof(argv[2]) : 20.0;
    g_threads = argc > 3 ? atoi(argv[3]) : 2;
    if (gb <= 0 || seconds <= 0 || g_threads < 1) return 2;

    g_len = (size_t)(gb * 1024.0 * 1024.0 * 1024.0);
    int flags = MAP_PRIVATE | MAP_ANONYMOUS;
    g_buf = mmap(NULL, g_len, PROT_READ | PROT_WRITE, flags, -1, 0);
    if (g_buf == MAP_FAILED) { perror("mmap"); return 1; }
    memset(g_buf, 1, g_len); /* 预触页，避免缺页在计时窗口内抖动 */

    pthread_t tids[8];
    for (int i = 0; i < g_threads && i < 8; i++) pthread_create(&tids[i], NULL, worker, (void *)(long)i);
    fprintf(stderr, "[mem_load] %.1f GB threads=%d duration=%.1fs start=%.3f\n", gb, g_threads, seconds, now_unix());
    usleep((useconds_t)(seconds * 1e6));
    atomic_store(&g_stop, 1);
    for (int i = 0; i < g_threads && i < 8; i++) pthread_join(tids[i], NULL);
    munmap(g_buf, g_len);
    fprintf(stderr, "[mem_load] done end=%.3f\n", now_unix());
    return 0;
}
