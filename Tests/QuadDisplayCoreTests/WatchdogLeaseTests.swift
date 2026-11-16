import XCTest
import Darwin
@testable import QuadDisplayCore

final class WatchdogLeaseTests: XCTestCase {
    func testBrokenHeartbeatPipeReturnsErrorWithoutTerminatingOwner() throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForWriting.close() }
        let descriptor = pipe.fileHandleForWriting.fileDescriptor
        try configureHeartbeatPipe(descriptor)
        XCTAssertNotEqual(fcntl(descriptor, F_GETFL) & O_NONBLOCK, 0)
        try pipe.fileHandleForReading.close()
        var byte: UInt8 = 0
        XCTAssertEqual(Darwin.write(descriptor, &byte, 1), -1)
        XCTAssertEqual(errno, EPIPE)
    }
    func testPreviewCannotBeExtendedByHeartbeat() {
        var lease = WatchdogLease(mode: .preview, started: 100)
        XCTAssertFalse(lease.receive("PING", at: 110))
        XCTAssertFalse(lease.expired(at: 124.9))
        XCTAssertTrue(lease.expired(at: 125))
    }
    func testSlowPreparationLeavesAFullVisiblePreviewPeriod() {
        var lease = WatchdogLease(mode: .preview, started: 100)
        XCTAssertTrue(lease.receive("VISIBLE", at: 120))
        XCTAssertFalse(lease.expired(at: 125))
        XCTAssertFalse(lease.expired(at: 135)) // Fifteen seconds of visible time.
        XCTAssertFalse(lease.expired(at: 144.9))
        XCTAssertTrue(lease.expired(at: 145))
    }
    func testPreviewVisibleTransitionCannotRepeatOrReviveAnExpiredLease() {
        var lease = WatchdogLease(mode: .preview, started: 0)
        XCTAssertTrue(lease.receive("VISIBLE", at: 24))
        XCTAssertFalse(lease.receive("VISIBLE", at: 30))
        XCTAssertFalse(lease.receive("PING", at: 40))
        XCTAssertTrue(lease.expired(at: 49))
        var expired = WatchdogLease(mode: .preview, started: 0)
        XCTAssertFalse(expired.receive("VISIBLE", at: 25))
        XCTAssertTrue(expired.expired(at: 26))
    }
    func testVisibleCommandDoesNotExtendWorkSessions() {
        var lease = WatchdogLease(mode: .work, started: 0)
        XCTAssertFalse(lease.receive("VISIBLE", at: 20))
        XCTAssertTrue(lease.expired(at: 25))
    }
    func testWorkHasBoundedStartupAndNoRevivalAfterExpiry() {
        var lease = WatchdogLease(mode: .work, started: 100)
        XCTAssertTrue(lease.expired(at: 125))
        XCTAssertFalse(lease.receive("PING", at: 125))
        XCTAssertTrue(lease.expired(at: 126))
    }
    func testResponsiveWorkContinuesButMissingHeartbeatExpires() {
        var lease = WatchdogLease(mode: .work, started: 0)
        XCTAssertTrue(lease.receive("PING", at: 3))
        for second in 4...3600 {
            XCTAssertFalse(lease.expired(at: Double(second)))
            XCTAssertTrue(lease.receive("PING", at: Double(second)))
        }
        XCTAssertFalse(lease.expired(at: 3609.9))
        XCTAssertTrue(lease.expired(at: 3610))
        XCTAssertFalse(lease.receive("PING", at: 3610))
    }
    func testUnexpectedCommandsNeverExtendLease() {
        for command in ["STOP", "", "PING PING", "PING\n", "anything"] {
            var lease = WatchdogLease(mode: .work, started: 0)
            XCTAssertFalse(lease.receive(command, at: 1))
            XCTAssertTrue(lease.expired(at: 25))
        }
    }
}
