import Foundation
import CoreGraphics

/// Coordinates use a top-left origin throughout. AppKit conversion happens at the boundary.
public enum Projection {
    public static func fittedRect(source: CGSize, in container: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / source.width, container.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    public static func sourcePoint(_ point: CGPoint, source: CGRect, viewport: CGRect, clamp: Bool = false) -> CGPoint? {
        let image = fittedRect(source: source.size, in: viewport)
        guard image.width > 0, image.height > 0 else { return nil }
        guard clamp || (point.x >= image.minX && point.x <= image.maxX && point.y >= image.minY && point.y <= image.maxY) else { return nil }
        let x = min(max((point.x - image.minX) / image.width, 0), 1)
        let y = min(max((point.y - image.minY) / image.height, 0), 1)
        // Half-open bounds: an event at maxX/maxY belongs to the next window.
        return CGPoint(x: source.minX + min(x * source.width, max(0, source.width - 0.01)),
                       y: source.minY + min(y * source.height, max(0, source.height - 0.01)))
    }

    public static func quartzRect(appKit: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: appKit.minX, y: primaryScreenHeight - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    public static func captureSize(source: CGSize, longestEdge: CGFloat = 1600) -> CGSize {
        guard source.width > 0, source.height > 0 else { return CGSize(width: 2, height: 2) }
        let scale = min(1, longestEdge / max(source.width, source.height))
        return CGSize(width: max(2, (source.width * scale).rounded()), height: max(2, (source.height * scale).rounded()))
    }
}

public struct WindowDescriptor: Equatable {
    public var title: String
    public var frame: CGRect
    public init(title: String, frame: CGRect) { self.title = title; self.frame = frame }
}

public struct IdentifiedWindowDescriptor {
    public var windowID: UInt32?
    public var window: WindowDescriptor
    public init(windowID: UInt32?, window: WindowDescriptor) { self.windowID = windowID; self.window = window }
}

public enum WindowMatcher {
    /// Window identity survives display changes and title edits; presentation
    /// geometry does not. Never replace a known, mismatching id with a heuristic.
    public static func bestMatch(windowID: UInt32, expected: WindowDescriptor, candidates: [IdentifiedWindowDescriptor]) -> Int? {
        let exact = candidates.indices.filter { candidates[$0].windowID == windowID }
        if exact.count == 1 { return exact[0] }
        if !exact.isEmpty || candidates.contains(where: { $0.windowID != nil }) { return nil }
        return bestMatch(for: expected, candidates: candidates.map(\.window))
    }
    private static func titlesAgree(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        if left.isEmpty || right.isEmpty { return false }
        // Chromium decorates AXTitle with the app/profile name; WindowServer does not.
        return [" - ", " — ", " – "].contains { separator in
            left.hasPrefix(right + separator) || right.hasPrefix(left + separator)
        }
    }
    /// Do not guess when two accessible windows are indistinguishable.
    public static func bestMatch(for expected: WindowDescriptor, candidates: [WindowDescriptor]) -> Int? {
        let scores = candidates.enumerated().map { index, candidate -> (Int, CGFloat) in
            let delta = abs(candidate.frame.minX - expected.frame.minX) + abs(candidate.frame.minY - expected.frame.minY)
                + abs(candidate.frame.width - expected.frame.width) + abs(candidate.frame.height - expected.frame.height)
            let titlePenalty: CGFloat = titlesAgree(candidate.title, expected.title) ? 0 : 10000
            return (index, delta + titlePenalty)
        }.sorted { $0.1 < $1.1 }
        guard let first = scores.first, first.1 < 8 else { return nil }
        if scores.count > 1, abs(scores[1].1 - first.1) < 0.1 { return nil }
        return first.0
    }
}

public struct SavedWindow: Codable, Equatable {
    public var windowID: UInt32
    public var processID: Int32
    public var bundleID: String
    public var launchDate: Date
    public var title: String
    public var originalFrame: CGRect
    public init(windowID: UInt32, processID: Int32, bundleID: String, launchDate: Date, title: String, originalFrame: CGRect) {
        self.windowID = windowID; self.processID = processID; self.bundleID = bundleID
        self.launchDate = launchDate; self.title = title; self.originalFrame = originalFrame
    }
}

public struct RecoveryStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> [SavedWindow] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SavedWindow].self, from: Data(contentsOf: url))
    }
    public func write(_ windows: [SavedWindow]) throws {
        if windows.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(windows).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
