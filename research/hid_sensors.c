/*
 * hid_sensors.c — MacTemp 传感器研究：读取 HID 温度传感器（含每核 pACC/eACC / PMU tdie 等）
 * MacTemp 传感器研究工具（不参与 App 构建）
 *
 * 由于 IOHIDEventSystemClient 私有/半公开头文件不在公开 SDK 中，这里用 dlsym 动态绑定
 * IOKit 导出的符号（只读，不写硬件，不需要 root）。
 *
 * 用法:
 *   ./hid_sensors list
 *   ./hid_sensors watch <seconds> <ms> <out.csv>
 *
 * 目的：为 SMC Tp/Te 键的 P/E 核归属提供**独立 ground truth**（HID 每核 die 温度）。
 */
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDServiceClientRef;
typedef void *IOHIDEventRef;

#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperatureLevel (15 << 16)
#define kIOHIDEventSystemClientTypeMonitor 1

static IOHIDEventSystemClientRef (*pCreate)(CFAllocatorRef);
static IOHIDEventSystemClientRef (*pCreateWithType)(CFAllocatorRef, int, CFDictionaryRef);
static CFArrayRef (*pCopyServices)(IOHIDEventSystemClientRef);
static CFTypeRef (*pCopyProperty)(IOHIDServiceClientRef, CFStringRef);
static IOHIDEventRef (*pCopyEvent)(IOHIDServiceClientRef, int, IOHIDEventRef, unsigned int);
static double (*pGetFloatValue)(IOHIDEventRef, int);

static double now_unix(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static int load_symbols(void) {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit", RTLD_LAZY);
    if (!h) { fprintf(stderr, "dlopen IOKit failed: %s\n", dlerror()); return 1; }
    pCreate = dlsym(h, "IOHIDEventSystemClientCreate");
    pCreateWithType = dlsym(h, "IOHIDEventSystemClientCreateWithType");
    pCopyServices = dlsym(h, "IOHIDEventSystemClientCopyServices");
    pCopyProperty = dlsym(h, "IOHIDServiceClientCopyProperty");
    pCopyEvent = dlsym(h, "IOHIDServiceClientCopyEvent");
    pGetFloatValue = dlsym(h, "IOHIDEventGetFloatValue");
    if (!pCopyServices || !pCopyProperty || !pCopyEvent || !pGetFloatValue || (!pCreate && !pCreateWithType)) {
        fprintf(stderr, "missing IOHID symbols\n");
        return 1;
    }
    return 0;
}

static IOHIDEventSystemClientRef make_client(void) {
    if (pCreateWithType) {
        IOHIDEventSystemClientRef c = pCreateWithType(kCFAllocatorDefault, kIOHIDEventSystemClientTypeMonitor, NULL);
        if (c) return c;
    }
    if (pCreate) return pCreate(kCFAllocatorDefault);
    return NULL;
}

static double read_temp(IOHIDServiceClientRef s, int *ok) {
    IOHIDEventRef ev = pCopyEvent(s, kIOHIDEventTypeTemperature, NULL, 0);
    if (!ev) { *ok = 0; return 0; }
    double v = pGetFloatValue(ev, kIOHIDEventFieldTemperatureLevel);
    CFRelease(ev);
    *ok = 1;
    return v;
}

static char *service_name(IOHIDServiceClientRef s) {
    static char buf[256];
    buf[0] = 0;
    CFTypeRef p = pCopyProperty(s, CFSTR("Product"));
    if (p) {
        if (CFGetTypeID(p) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)p, buf, sizeof(buf), kCFStringEncodingUTF8);
        CFRelease(p);
    }
    return buf;
}

int main(int argc, char **argv) {
    if (load_symbols() != 0) return 1;
    IOHIDEventSystemClientRef client = make_client();
    if (!client) { fprintf(stderr, "cannot create IOHIDEventSystemClient\n"); return 1; }
    CFArrayRef services = pCopyServices(client);
    if (!services) { fprintf(stderr, "no services\n"); return 2; }
    CFIndex n = CFArrayGetCount(services);

    const char *mode = argc > 1 ? argv[1] : "list";
    if (strcmp(mode, "list") == 0) {
        int shown = 0;
        printf("HID services: %ld\n", (long)n);
        for (CFIndex i = 0; i < n; i++) {
            IOHIDServiceClientRef s = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            int ok = 0;
            double v = read_temp(s, &ok);
            char *name = service_name(s);
            if (ok) { printf("%-56s %8.2f\n", name[0] ? name : "(noname)", v); shown++; }
            else if (argc > 2 && strcmp(argv[2], "all") == 0) { printf("%-56s %s\n", name[0] ? name : "(noname)", "n/a"); }
        }
        printf("total temperature services: %d\n", shown);
        return 0;
    }

    if (strcmp(mode, "watch") == 0) {
        if (argc < 5) { fprintf(stderr, "usage: %s watch <seconds> <ms> <out.csv>\n", argv[0]); return 2; }
        double seconds = atof(argv[2]);
        int ms = atoi(argv[3]);
        FILE *f = fopen(argv[4], "w");
        if (!f) { perror("fopen"); return 3; }
        fprintf(f, "t_unix,name,value\n");
        double end = now_unix() + seconds;
        while (now_unix() < end) {
            double t = now_unix();
            for (CFIndex i = 0; i < n; i++) {
                IOHIDServiceClientRef s = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
                int ok = 0;
                double v = read_temp(s, &ok);
                if (!ok) continue;
                char *name = service_name(s);
                fprintf(f, "%.3f,%s,%.4f\n", t, name[0] ? name : "(noname)", v);
            }
            fflush(f);
            double dt = (double)ms / 1000.0 - (now_unix() - t);
            if (dt > 0) usleep((useconds_t)(dt * 1e6));
        }
        fclose(f);
        printf("HID watch done -> %s\n", argv[4]);
        return 0;
    }

    fprintf(stderr, "unknown mode\n");
    return 2;
}
