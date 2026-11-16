import Foundation
import CoreGraphics
import QuadDisplayCore
import Darwin
import AppKit
import OSLog

// Bundled child process: snapshot is taken BEFORE the parent creates any display.
// No third-party PID is accepted as an argument. This helper controls only its parent.
let parent = getppid()
guard CommandLine.arguments.count == 2,
      ["--guard-preview", "--guard-work"].contains(CommandLine.arguments[1]), parent > 1 else { exit(64) }
let contents = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent()
let owners = ["io.github.TRN408.QuadDeskNativePreview": "QuadDeskNativePreview", "io.github.TRN408.QuadDesk": "QuadDesk"]
func ownsParent() -> Bool {
    guard getppid() == parent, let owner = NSRunningApplication(processIdentifier: parent) else { return false }
    guard let name = owners[owner.bundleIdentifier ?? ""] else { return false }
    return owner.executableURL?.resolvingSymlinksInPath() == contents.appendingPathComponent("MacOS/\(name)")
}
guard ownsParent() else { exit(64) }
signal(SIGPIPE, SIG_IGN)
let logger = Logger(subsystem: "io.github.TRN408.QuadDesk", category: "DisplayWatchdog")
do {
    let snapshot = try DisplaySnapshot.captureSingleDisplay()
    print("READY \(snapshot.id) \(snapshot.mode.ioDisplayModeID)"); fflush(stdout)
    let pipe = FileHandle.standardInput
    var finished = false
    func uptime() -> TimeInterval { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
    var lease = WatchdogLease(mode: CommandLine.arguments[1] == "--guard-work" ? .work : .preview, started: uptime())
    var input = Data()
    func finish(deadline: Bool) {
        guard !finished else { return }; finished = true
        pipe.readabilityHandler = nil
        if deadline, ownsParent() {
            logger.error("Owner response deadline expired; terminating own parent pid=\(parent)")
            kill(parent, SIGTERM)
        }
        // Display teardown happens asynchronously after the owner releases it/exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            do {
                try snapshot.restore()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if snapshot.verifyRestored() {
                        logger.notice("Original single-display configuration restored")
                        print("RESTORED"); fflush(stdout); exit(0)
                    }
                    print("ERROR 復元後の表示構成を確認できません。"); fflush(stdout); exit(2)
                }
            } catch { print("ERROR \(error.localizedDescription)"); fflush(stdout); exit(1) }
        }
    }
    pipe.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty { handle.readabilityHandler = nil }
        DispatchQueue.main.async {
            guard !finished else { return }
            guard !data.isEmpty else { finish(deadline: false); return }
            input.append(data)
            guard input.count <= 1024 else { finish(deadline: false); return }
            while let end = input.firstIndex(of: 10) {
                let line = String(decoding: input[..<end], as: UTF8.self)
                input.removeSubrange(...end)
                guard lease.receive(line, at: uptime()) else { finish(deadline: false); return }
            }
        }
    }
    let timer = Timer(timeInterval: 1, repeats: true) { _ in
        if lease.expired(at: uptime()) { finish(deadline: true) }
    }
    RunLoop.main.add(timer, forMode: .common)
    DispatchQueue.main.asyncAfter(deadline: .now() + NativePreviewPlan.watchdogSeconds) {
        if lease.expired(at: uptime()) { finish(deadline: true) }
    }
    RunLoop.main.run()
} catch { print("ERROR \(error.localizedDescription)"); fflush(stdout); exit(1) }
