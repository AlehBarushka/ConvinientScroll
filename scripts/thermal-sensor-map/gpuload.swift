import Foundation
import Metal
let seconds = Double(CommandLine.arguments[1]) ?? 90
let device = MTLCreateSystemDefaultDevice()!
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void burn(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    float a = float(id) * 0.001f, b = 1.0001f;
    for (int i = 0; i < 20000; i++) { a = fma(a, b, 0.0001f); b = fma(b, 0.99999f, 0.00001f); }
    out[id] = a + b;
}
"""
let lib = try! device.makeLibrary(source: src, options: nil)
let pso = try! device.makeComputePipelineState(function: lib.makeFunction(name: "burn")!)
let queue = device.makeCommandQueue()!
let n = 1 << 20
let buf = device.makeBuffer(length: n * 4, options: .storageModePrivate)!
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    let cb = queue.makeCommandBuffer()!
    let enc = cb.makeComputeCommandEncoder()!
    enc.setComputePipelineState(pso)
    enc.setBuffer(buf, offset: 0, index: 0)
    enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    enc.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
}
