// metal_load.swift — MacTemp 传感器研究：GPU 负载发生器（Metal 计算空转）
// MacTemp 传感器研究工具（不参与 App 构建）
//
// 用法: ./metal_load <seconds> [dispatchPerSec]
// 运行时用 MSL 源码字符串编译 kernel（无需 xcrun metal），循环 dispatch 到指定秒数。
// 结束后退出，不残留。
import Foundation
import Metal

let args = CommandLine.arguments
guard args.count >= 2, let seconds = Double(args[1]), seconds > 0 else {
    FileHandle.standardError.write("usage: metal_load <seconds> [dispatchesPerSecond]\n".data(using: .utf8)!)
    exit(2)
}
let rate = args.count >= 3 ? max(1, Int(args[2]) ?? 600) : 600

guard let device = MTLCreateSystemDefaultDevice() else {
    FileHandle.standardError.write("no Metal device\n".data(using: .utf8)!)
    exit(1)
}

let src = """
#include <metal_stdlib>
using namespace metal;
kernel void spin(device float *out [[buffer(0)]],
                 constant uint &seed [[buffer(1)]],
                 uint gid [[thread_position_in_grid]]) {
    float x = float(seed + gid) * 1.0000001192092896f + 0.0001f;
    float acc = 0.0f;
    for (uint i = 0; i < 80000u; i++) {
        x = fma(x, 1.0000001192092896f, 0.000001f);
        acc += x;
        if (x > 1.0e9f) x = 1.0f + float(gid);
    }
    out[gid] = acc + x;
}
"""

let startTime = Date()
var queue: MTLCommandQueue? = device.makeCommandQueue()
guard let cmdQueue = queue else {
    FileHandle.standardError.write("no command queue\n".data(using: .utf8)!)
    exit(1)
}

let library: MTLLibrary
do {
    library = try device.makeLibrary(source: src, options: nil)
} catch {
    FileHandle.standardError.write("metal compile failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
guard let fn = library.makeFunction(name: "spin") else {
    FileHandle.standardError.write("no kernel fn\n".data(using: .utf8)!)
    exit(1)
}
let pipeline: MTLComputePipelineState
do {
    pipeline = try device.makeComputePipelineState(function: fn)
} catch {
    FileHandle.standardError.write("pipeline failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

let threadWidth = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
let threadsPerGroup = MTLSize(width: threadWidth, height: 1, depth: 1)
let grid = MTLSize(width: 32768, height: 1, depth: 1)
let outBuf = device.makeBuffer(length: grid.width * MemoryLayout<Float>.stride, options: .storageModeShared)!

FileHandle.standardError.write("[metal_load] device=\(device.name) rate=\(rate)/s duration=\(seconds)s\n".data(using: .utf8)!)

var dispatches = 0
var seed: UInt32 = 1
let deadline = startTime.addingTimeInterval(seconds)
let interval = 1.0 / Double(rate)
var next = Date()
while Date() < deadline {
    let seedBuf = withUnsafeBytes(of: &seed) { device.makeBuffer(bytes: $0.baseAddress!, length: 4, options: .storageModeShared)! }
    guard let cb = cmdQueue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { break }
    enc.setComputePipelineState(pipeline)
    enc.setBuffer(outBuf, offset: 0, index: 0)
    enc.setBuffer(seedBuf, offset: 0, index: 1)
    enc.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
    enc.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
    dispatches += 1
    seed = seed &* 1664525 &+ 1013904223
    next = next.addingTimeInterval(interval)
    let wait = next.timeIntervalSinceNow
    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
}
FileHandle.standardError.write("[metal_load] done dispatches=\(dispatches)\n".data(using: .utf8)!)
