import Foundation

/// Bound only top-level URL loads. Loaded pages, their timers and network
/// updates remain live. A stale completion cannot release a newer job's slot.
@MainActor
final class BrowserNavigationQueue {
    private struct Job {
        let key: UUID
        let ticket = UUID()
        let start: (@escaping () -> Void) -> Void
        let cancel: () -> Void
    }
    private let limit: Int
    private var waiting: [Job] = []
    private var active: [UUID: Job] = [:]
    private var draining = false
    var activeCount: Int { active.count }
    var waitingCount: Int { waiting.count }

    init(limit: Int = 2) { self.limit = max(1, limit) }

    func enqueue(key: UUID, start: @escaping (@escaping () -> Void) -> Void, cancel: @escaping () -> Void) {
        remove(key: key)
        waiting.append(Job(key: key, start: start, cancel: cancel))
        drain()
    }
    func cancel(key: UUID) { remove(key: key); drain() }
    func cancelAll() {
        waiting.removeAll()
        let jobs = Array(active.values); active.removeAll()
        jobs.forEach { $0.cancel() }
    }
    private func remove(key: UUID) {
        waiting.removeAll { $0.key == key }
        let jobs = active.filter { $0.value.key == key }
        for (ticket, job) in jobs { active.removeValue(forKey: ticket); job.cancel() }
    }
    private func drain() {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while active.count < limit, !waiting.isEmpty {
            let job = waiting.removeFirst()
            active[job.ticket] = job
            job.start { [weak self] in
                guard let self, self.active.removeValue(forKey: job.ticket) != nil else { return }
                self.drain()
            }
        }
    }
}
