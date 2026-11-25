import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics

// 录像: the camera's
// video. What the upper screen shows — the module's look, the lens, the
// body, 闪闪's pieces — written frame by frame at the camera's 640 × 480
// into an MP4 (H.264), with the microphone's sound (AAC) when the iPhone's
// microphone may be used; at most ten minutes.
// The file is written in the app's temporary folder and moved onto the SD
// card under the pictures' next number when it is finished.

/// Writes one video. Frames come on the camera's frame queue, sound on its
/// audio queue; everything goes through one lock.
final class CameraRecorder: @unchecked Sendable {
    let url: URL
    /// Ten minutes at most.
    static let limit = 600.0
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audio: AVAssetWriterInput?
    private let lock = NSLock()
    private var started = false
    private var finishing = false
    private var first = CMTime.invalid
    private var last = CMTime.invalid
    private var frames = 0
    private var sounds = 0

    /// A new recording into the app's temporary folder.
    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FoldArc-video-\(UUID().uuidString).mp4")
    }

    init(url: URL, audio withSound: Bool, size: CGSize = CameraLook.photoSize) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(size.width), height = Int(size.height)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_400_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(video) else { throw CameraFailure(message: String(localized: "录像写不了画面")) }
        writer.add(video)
        if withSound {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 96_000,
            ])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input); audio = input } else { audio = nil }
        } else {
            audio = nil
        }
        guard writer.startWriting() else { throw CameraFailure(message: writer.error?.localizedDescription ?? String(localized: "录像没能开始")) }
    }

    /// How long it is so far (seconds), from its first frame to the last.
    var seconds: Double {
        lock.lock(); defer { lock.unlock() }
        guard first.isValid, last.isValid else { return 0 }
        return (last - first).seconds
    }
    var hasSound: Bool { audio != nil }

    /// A frame the camera made (`time`: its time on the camera's clock, s).
    func append(_ image: CIImage, context: CIContext, at time: Double) {
        lock.lock(); defer { lock.unlock() }
        guard let buffer = nextBuffer(at: time) else { return }
        context.render(image, to: buffer, bounds: CameraLook.photoRect, colorSpace: CameraLook.colorSpace)
        push(buffer, at: time)
    }

    /// A frame already drawn (闪闪's pieces over the picture).
    func append(_ image: CGImage, at time: Double) {
        lock.lock(); defer { lock.unlock() }
        guard let buffer = nextBuffer(at: time) else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer),
           let c = CGContext(data: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                             bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CameraLook.colorSpace,
                             bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
            c.draw(image, in: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        push(buffer, at: time)
    }

    /// The microphone's sound (on the same clock as the frames).
    func appendSound(_ sample: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard started, !finishing, let audio, writer.status == .writing, audio.isReadyForMoreMediaData else { return }
        guard CMSampleBufferGetPresentationTimeStamp(sample) >= first else { return }
        if audio.append(sample) { sounds += 1 }
    }

    /// The writing has stopped by itself (the card full, the file gone):
    /// nothing more goes into it.
    var failed: Bool {
        lock.lock(); defer { lock.unlock() }
        return started && !finishing && writer.status == .failed
    }

    /// Ends it: the file is complete when `done` is called (on any queue).
    func finish(_ done: @escaping @Sendable (Result<URL, CameraFailure>) -> Void) {
        lock.lock()
        let wasStarted = started, already = finishing
        finishing = true
        let counts = (frames, sounds)
        lock.unlock()
        guard !already else { return }
        guard wasStarted, counts.0 > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            done(.failure(CameraFailure(message: String(localized: "没录到画面"))))
            return
        }
        // (A writer that stopped by itself has nothing to finish.)
        guard writer.status == .writing else {
            let message = writer.error?.localizedDescription ?? String(localized: "录像没写完")
            try? FileManager.default.removeItem(at: url)
            done(.failure(CameraFailure(message: message)))
            return
        }
        video.markAsFinished()
        audio?.markAsFinished()
        let writer = self.writer, url = self.url
        writer.finishWriting {
            if writer.status == .completed {
                NSLog("[camera] video: %d frames, %d pieces of sound", counts.0, counts.1)
                done(.success(url))
            } else {
                done(.failure(CameraFailure(message: writer.error?.localizedDescription ?? String(localized: "录像没写完"))))
            }
        }
    }

    // MARK: Under the lock

    private func nextBuffer(at time: Double) -> CVPixelBuffer? {
        guard !finishing, writer.status == .writing else { return nil }
        let t = CMTime(seconds: time, preferredTimescale: 600)
        if !started {
            writer.startSession(atSourceTime: t)
            started = true
            first = t
        }
        guard video.isReadyForMoreMediaData, !last.isValid || t > last, let pool = adaptor.pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }
    private func push(_ buffer: CVPixelBuffer, at time: Double) {
        let t = CMTime(seconds: time, preferredTimescale: 600)
        if adaptor.append(buffer, withPresentationTime: t) {
            frames += 1
            last = t
        }
    }
}

extension CameraRoll {
    /// A video's first picture (the album's), at most `maxPixel` across.
    static func poster(at url: URL, maxPixel: Int) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let image: CGImage? = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: CMTime(seconds: 0.05, preferredTimescale: 600)) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
        return image
    }
    /// How long a video is (seconds).
    static func duration(of url: URL) async -> Double? {
        guard let time = try? await AVURLAsset(url: url).load(.duration), time.seconds.isFinite else { return nil }
        return time.seconds
    }
    /// A recording moved onto the card under the next free number (….MP4).
    static func saveVideo(from file: URL, in dcim: URL = CameraRoll.dcim) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dcim, withIntermediateDirectories: true)
        let folders = (try? fm.contentsOfDirectory(atPath: dcim.path)) ?? []
        guard let next = CameraFileNames.next(folders: folders, files: { (try? fm.contentsOfDirectory(atPath: dcim.appendingPathComponent($0).path)) ?? [] }, ext: "MP4") else {
            throw NSError(domain: "FoldArc.camera", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "SD 卡上的编号用完了")])
        }
        let folder = dcim.appendingPathComponent(next.folder, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(next.file)
        guard !fm.fileExists(atPath: url.path) else {
            throw NSError(domain: "FoldArc.camera", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "\(next.file) 已经有了")])
        }
        try fm.moveItem(at: file, to: url)
        return url
    }
}
