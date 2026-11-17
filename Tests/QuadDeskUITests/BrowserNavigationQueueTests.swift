import XCTest
@testable import QuadDesk

final class BrowserNavigationQueueTests: XCTestCase {
    @MainActor
    func testSixteenRequestsRunAtMostTwoAtATimeWithoutDroppingAny() {
        let queue = BrowserNavigationQueue()
        var started: [Int] = []
        var finished: [Int: () -> Void] = [:]
        for index in 0..<16 {
            queue.enqueue(key: UUID(), start: { done in started.append(index); finished[index] = done }, cancel: {})
        }
        XCTAssertEqual(started, [0, 1])
        XCTAssertEqual(queue.waitingCount, 14)
        for index in 0..<16 { finished[index]?(); XCTAssertLessThanOrEqual(queue.activeCount, 2) }
        XCTAssertEqual(started, Array(0..<16))
        XCTAssertEqual(queue.activeCount, 0)
        XCTAssertEqual(queue.waitingCount, 0)
    }
    @MainActor
    func testReplacingRequestIgnoresOldCompletionAndClosingReleasesSlot() {
        let queue = BrowserNavigationQueue(limit: 1)
        let key = UUID()
        var old: (() -> Void)?, current: (() -> Void)?
        var cancellations = 0, laterStarted = false
        queue.enqueue(key: key, start: { old = $0 }, cancel: { cancellations += 1 })
        queue.enqueue(key: key, start: { current = $0 }, cancel: { cancellations += 1 })
        queue.enqueue(key: UUID(), start: { _ in laterStarted = true }, cancel: {})
        old?()
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(queue.activeCount, 1)
        XCTAssertFalse(laterStarted)
        current?()
        XCTAssertTrue(laterStarted)
        queue.cancelAll()
        XCTAssertEqual(queue.activeCount, 0)
    }
    @MainActor
    func testSynchronousCompletionDoesNotDeadlockAndCancelDropsQueuedWork() {
        let queue = BrowserNavigationQueue(limit: 1)
        var hold: (() -> Void)?, ran = false
        queue.enqueue(key: UUID(), start: { hold = $0 }, cancel: {})
        let key = UUID()
        queue.enqueue(key: key, start: { done in ran = true; done() }, cancel: {})
        queue.cancel(key: key)
        hold?()
        XCTAssertFalse(ran)
        queue.enqueue(key: UUID(), start: { done in ran = true; done() }, cancel: {})
        XCTAssertTrue(ran)
        XCTAssertEqual(queue.activeCount, 0)
    }
}
