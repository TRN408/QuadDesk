import Foundation

/// The size is in CSS points. Overflow scrolls instead of shrinking web pages.
public enum MobileViewport: Int, CaseIterable {
    case compact = 320, standard = 390, wide = 430, desktop = 1024
    public var title: String { self == .desktop ? "PC · 1024" : "モバイル · \(rawValue)" }
    public var isMobile: Bool { self != .desktop }
}

public enum BrowserAddress {
    /// Treat bare hosts as HTTPS; do not interpret arbitrary text as a script or file URL.
    public static func resolve(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let explicit = value.contains("://")
        let candidate = explicit ? value : "https://" + value
        guard let parts = URLComponents(string: candidate),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              !host.contains("%"),
              explicit || host == "localhost" || host.contains("."),
              let url = parts.url else { return nil }
        return url
    }

    public static func allowsNavigation(to url: URL, isMainFrame: Bool = true) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https"].contains(scheme) || url.absoluteString == "about:blank" { return true }
        // Inline frames are part of normal web pages, never an external-app launch.
        return !isMainFrame && (["blob", "data"].contains(scheme) || url.absoluteString == "about:srcdoc")
    }
}
