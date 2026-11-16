import AppKit
import ScreenCaptureKit
import AVFoundation
import QuadCore

final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "app.quaddesk.capture", qos: .userInitiated)
    private let lock = NSLock()
    private var latest: CMSampleBuffer?
    private var deliveryPending = false
    private var stopped = false
    private let background = CGColor(gray: 0, alpha: 1)
    private var sourceSize = CGSize.zero
    private var desiredProfile = CaptureProfile(active: false)
    private var appliedProfile = CaptureProfile(active: false)
    private var configurationTask: Task<Void, Never>?
    private var running = false
    private var received = 0
    private var delivered = 0
    private var coalesced = 0
    private var activity = ProcessInfo.processInfo.systemUptime
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onError: ((CaptureFailure) -> Void)?

    @MainActor func start(window: SCWindow, size: CGSize) async throws {
        sourceSize = size
        let initial = desiredProfile
        let config = configuration(for: initial)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        appliedProfile = initial
        running = true
        applyPriorityIfNeeded()
    }

    private func configuration(for profile: CaptureProfile) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let dimensions = profile.dimensions(for: sourceSize)
        config.width = Int(dimensions.width)
        config.height = Int(dimensions.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: profile.framesPerSecond)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.backgroundColor = background
        return config
    }

    @MainActor func setPriority(active: Bool, constrained: Bool) {
        desiredProfile = CaptureProfile(active: active, constrained: constrained)
        applyPriorityIfNeeded()
    }

    @MainActor private func applyPriorityIfNeeded() {
        guard running, configurationTask == nil, desiredProfile != appliedProfile else { return }
        // Serialize and coalesce rapid focus changes; never race configuration updates.
        configurationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.configurationTask = nil }
            while !Task.isCancelled, let stream = self.stream,
                  !self.lock.withLock({ self.stopped }), self.desiredProfile != self.appliedProfile {
                let next = self.desiredProfile
                do {
                    try await stream.updateConfiguration(self.configuration(for: next))
                    guard !Task.isCancelled, self.stream === stream else { return }
                    self.appliedProfile = next
                } catch {
                    if !Task.isCancelled { self.notifyFailure(error) }
                    return
                }
            }
        }
    }

    @MainActor func health() -> String {
        let counts = lock.withLock { (received, delivered, coalesced, activity, stopped) }
        return "received=\(counts.0) delivered=\(counts.1) coalesced=\(counts.2) callbackAge=\(Int(ProcessInfo.processInfo.systemUptime - counts.3))s stopped=\(counts.4) fps=\(appliedProfile.framesPerSecond)"
    }

    @MainActor func stop() async {
        running = false
        configurationTask?.cancel(); configurationTask = nil
        lock.withLock { stopped = true; latest = nil }
        if let stream { try? await stream.stopCapture() }
        stream = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        notifyFailure(error)
    }

    private func notifyFailure(_ error: Error) {
        let shouldNotify = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            stopped = true
            latest = nil
            return true
        }
        guard shouldNotify else { return }
        let failure = CaptureFailure(error: error)
        DispatchQueue.main.async { [weak self] in self?.onError?(failure) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen { lock.withLock { activity = ProcessInfo.processInfo.systemUptime } }
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        // Display immediately, without creating a second timing clock or copying the pixels.
        if let sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(sampleAttachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        received += 1
        if latest != nil { coalesced += 1 }
        latest = sampleBuffer
        guard !deliveryPending else { lock.unlock(); return }
        deliveryPending = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let frame = self.latest
            self.latest = nil
            self.deliveryPending = false
            let stopped = self.stopped
            self.lock.unlock()
            if !stopped, let frame {
                self.lock.withLock { self.delivered += 1 }
                self.onFrame?(frame)
            }
        }
    }
}
