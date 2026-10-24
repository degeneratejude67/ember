import AVKit
import SwiftUI
import UIKit

/// A floating mini timer for blocks spent in another app (CollaNote, Slate...). It is a
/// Picture in Picture window fed with frames drawn here once a second, so it floats over any
/// app and can be moved or tucked to the side. Tapping its restore button returns to Ember.
///
/// PiP starts by itself when Ember goes to the background while the inline preview (shown on
/// the focus screen) is on screen and playing.
final class FloatingTimer: NSObject, ObservableObject {
    static let shared = FloatingTimer()

    @Published private(set) var floating = false
    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var ticker: Timer?
    private var content: () -> Frame? = { nil }

    struct Frame: Equatable {
        var time: String
        var caption: String
        var tier: FlameTier
        var paused: Bool
    }

    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    var isRunning: Bool { ticker != nil }

    private override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        let timebase = try? CMTimebase(sourceClock: .hostTimeClock)
        try? timebase?.setTime(.zero)
        try? timebase?.setRate(1)
        displayLayer.controlTimebase = timebase
    }

    /// Starts drawing frames for the running block. `content` returns nil once there is
    /// nothing to show, which stops the timer.
    func run(_ content: @escaping () -> Frame?) {
        self.content = content
        draw()
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.draw() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        prepareController()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        controller?.stopPictureInPicture()
        content = { nil }
    }

    private func prepareController() {
        guard controller == nil, Self.isSupported, !AppEnv.isUITest else { return }
        // PiP needs a playback audio session; it stays silent and mixes with other audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pip.requiresLinearPlayback = true
        pip.delegate = self
        controller = pip
    }

    private func draw() {
        guard let frame = content() else {
            stop()
            return
        }
        guard let buffer = Self.render(frame), let sample = Self.sample(buffer) else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }

    // MARK: - Drawing

    private static let size = CGSize(width: 480, height: 270)

    /// Draws the mini timer into a pixel buffer: the flame on the left, the time and the
    /// subject on the right.
    static func render(_ frame: Frame) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // UIKit drawing expects the origin at the top left
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        UIColor(red: 0.055, green: 0.059, blue: 0.075, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))

        let flameRect = CGRect(x: 34, y: 55, width: 128, height: 160)
        let outer = FlameShape().path(in: flameRect).cgPath
        let core = FlameCoreShape().path(in: flameRect).cgPath
        let colors = frame.paused ? FlameTier.ash : frame.tier
        context.addPath(outer)
        context.setFillColor(UIColor(colors.outer[0]).cgColor)
        context.fillPath()
        context.addPath(core)
        context.setFillColor(UIColor(colors.core[1]).cgColor)
        context.fillPath()

        let time = NSAttributedString(string: frame.time, attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 92, weight: .heavy).rounded,
            .foregroundColor: UIColor.white,
        ])
        time.draw(at: CGPoint(x: 190, y: 62))
        let caption = NSAttributedString(string: frame.caption, attributes: [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold).rounded,
            .foregroundColor: UIColor(white: 0.62, alpha: 1),
        ])
        caption.draw(in: CGRect(x: 192, y: 170, width: 270, height: 40))
        return buffer
    }

    static func sample(_ buffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

extension FloatingTimer: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {}

    /// A live stream: no seeking, no scrubber.
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }

    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension FloatingTimer: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.floating = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        DispatchQueue.main.async { self.floating = false }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// The inline preview of the floating timer. It has to be on screen and playing when Ember
/// goes to the background for Picture in Picture to start by itself.
struct FloatingTimerPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewView { PreviewView() }
    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(FloatingTimer.shared.displayLayer)
            layer.cornerRadius = 14
            clipsToBounds = true
            backgroundColor = .black
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            if FloatingTimer.shared.displayLayer.superlayer !== layer { layer.addSublayer(FloatingTimer.shared.displayLayer) }
            FloatingTimer.shared.displayLayer.frame = bounds
        }
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
