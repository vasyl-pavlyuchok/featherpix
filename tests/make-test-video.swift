// Writes a synthetic test video (moving gradient + 440 Hz tone) so the video tests never need real footage.
// Usage: make-test-video <out.mp4|.mov> [seconds] [width] [height] [--rotate90] [--no-audio]
import Foundation
import AVFoundation
import CoreVideo

let a = CommandLine.arguments
guard a.count > 1 else { print("usage: make-test-video out.mp4 [sec] [w] [h] [--rotate90] [--no-audio]"); exit(2) }
let out = URL(fileURLWithPath: a[1])
let secs = a.count > 2 ? Double(a[2]) ?? 3 : 3
let W = a.count > 3 ? Int(a[3]) ?? 1920 : 1920
let H = a.count > 4 ? Int(a[4]) ?? 1080 : 1080
let rotate = a.contains("--rotate90")
let audio = !a.contains("--no-audio")
let fps = 24
try? FileManager.default.removeItem(at: out)

let w = try AVAssetWriter(outputURL: out, fileType: out.pathExtension.lowercased() == "mov" ? .mov : .mp4)
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
])
vIn.expectsMediaDataInRealTime = false
if rotate { vIn.transform = CGAffineTransform(rotationAngle: .pi / 2) }
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
w.add(vIn)
var aIn: AVAssetWriterInput? = nil
if audio {
    let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100, AVEncoderBitRateKey: 128_000,
    ])
    ai.expectsMediaDataInRealTime = false
    w.add(ai); aIn = ai
}
guard w.startWriting() else { print("cannot write: \(w.error?.localizedDescription ?? "?")"); exit(1) }
w.startSession(atSourceTime: .zero)

let frames = Int(secs * Double(fps))
let rate = 44_100, chunk = 1024
let totalSamples = Int(secs * Double(rate))
var fmt = AudioStreamBasicDescription(mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
                                      mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                                      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                      mBitsPerChannel: 16, mReserved: 0)
var desc: CMAudioFormatDescription?
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &fmt, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &desc)
var s = 0

func audioBuffer(_ n: Int) -> CMSampleBuffer {
    var pcm = [Int16](repeating: 0, count: n)
    for k in 0..<n { pcm[k] = Int16(sin(2 * .pi * 440 * Double(s + k) / Double(rate)) * 8000) }
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 2, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: n * 2, flags: 0, blockBufferOut: &block)
    pcm.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: n * 2) }
    var sb: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: desc!, sampleCount: n,
                                                          presentationTimeStamp: CMTime(value: CMTimeValue(s), timescale: CMTimeScale(rate)),
                                                          packetDescriptions: nil, sampleBufferOut: &sb)
    return sb!
}

func frame(_ i: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let p = pb!
    let t = Double(i) / Double(fps)
    CVPixelBufferLockBaseAddress(p, [])
    let base = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
    let bpr = CVPixelBufferGetBytesPerRow(p)
    for y in 0..<H {
        let row = base + y * bpr
        for x in 0..<W {
            let o = x * 4
            row[o] = UInt8((Double(x) / Double(W) * 200 + t * 40).truncatingRemainder(dividingBy: 255))
            row[o + 1] = UInt8((Double(y) / Double(H) * 180 + 30))
            row[o + 2] = UInt8(((Double(x + y) / Double(W + H)) * 255 + t * 60).truncatingRemainder(dividingBy: 255))
            row[o + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(p, [])
    return p
}

// One queue per track; AVAssetWriter decides the interleaving.
let group = DispatchGroup()
var fi = 0
group.enter()
vIn.requestMediaDataWhenReady(on: DispatchQueue(label: "v")) {
    while vIn.isReadyForMoreMediaData {
        if fi >= frames { vIn.markAsFinished(); group.leave(); return }
        adaptor.append(frame(fi), withPresentationTime: CMTime(value: CMTimeValue(fi), timescale: CMTimeScale(fps)))
        fi += 1
    }
}
if let ai = aIn {
    group.enter()
    ai.requestMediaDataWhenReady(on: DispatchQueue(label: "a")) {
        while ai.isReadyForMoreMediaData {
            if s >= totalSamples { ai.markAsFinished(); group.leave(); return }
            let n = min(chunk, totalSamples - s)
            ai.append(audioBuffer(n))
            s += n
        }
    }
}
group.wait()
let sem = DispatchSemaphore(value: 0)
w.finishWriting { sem.signal() }
sem.wait()
if w.status != .completed { print("failed: \(w.error?.localizedDescription ?? "?")"); exit(1) }
print("wrote \(out.path)")
