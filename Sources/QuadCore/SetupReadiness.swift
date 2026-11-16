/// Setup requirements are evaluated without requesting OS permissions or
/// creating a display. Losing a permission immediately makes setup unready.
public struct SetupReadiness {
    public let screenRecording: Bool
    public let accessibility: Bool
    public let selections: [UInt32?]
    public let isBusy: Bool
    public init(screenRecording: Bool, accessibility: Bool, selections: [UInt32?], isBusy: Bool = false) {
        self.screenRecording = screenRecording; self.accessibility = accessibility
        self.selections = selections; self.isBusy = isBusy
    }
    public var permissionsGranted: Bool { screenRecording && accessibility }
    public var hasFourDistinctWindows: Bool {
        selections.count == 4 && selections.allSatisfy { $0 != nil }
            && Set(selections.compactMap { $0 }).count == 4
    }
    public var canChooseWindows: Bool { permissionsGranted && !isBusy }
    public var canStart: Bool { canChooseWindows && hasFourDistinctWindows }
}
