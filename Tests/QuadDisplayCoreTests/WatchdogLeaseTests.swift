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
