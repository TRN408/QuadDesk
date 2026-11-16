public struct WindowMenuEntry: Equatable {
    public let id: UInt32
    public let title: String
    public init(id: UInt32, title: String) { self.id = id; self.title = title }

    public static func retainedSelections(_ selected: [UInt32?], available: Set<UInt32>) -> [UInt32?] {
        selected.map { id in id.flatMap { available.contains($0) ? $0 : nil } }
    }

    /// NSPopUpButton's title-based insertion can collapse duplicate names. Keep
    /// window identities distinct and make their displayed names unambiguous.
    public static func unique(_ entries: [Self]) -> [Self] {
        var seen: Set<UInt32> = []
        var titles: Set<String> = []
        return entries.compactMap { entry in
            guard seen.insert(entry.id).inserted else { return nil }
            var title = entry.title, suffix = 2
            while titles.contains(title) { title = "\(entry.title)（\(suffix)）"; suffix += 1 }
            titles.insert(title)
            return Self(id: entry.id, title: title)
        }
    }
}
