import AppKit

// terminateLater pumps NSModalPanelRunLoopMode, possibly from inside a main
// dispatch block. That queue cannot reenter itself to deliver capture replies.
// Schedule acknowledgements and the deadline on the run loop itself instead.
enum CaptureRunLoop {
    static func perform(_ body: @escaping () -> Void) {
        let loop = CFRunLoopGetMain()
        let modes = [RunLoop.Mode.common.rawValue, RunLoop.Mode.modalPanel.rawValue] as CFArray
        CFRunLoopPerformBlock(loop, modes, body)
        CFRunLoopWakeUp(loop)
    }
    static func deadline(after seconds: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in body() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        return timer
    }
}

// Main-thread confined. Operations must deliver their completion on main too.
// A frame may arrive before ScreenCaptureKit finishes starting: defer retirement
// until that callback, and retain every stream until its stop callback returns.
final class CaptureLifecycle {
    typealias Operation = (@escaping (Error?) -> Void) -> Void
    private final class Session {
        enum State { case starting, running, stopping }
        var state = State.starting
        var stopRequested = false
        let stop: Operation
        init(stop: @escaping Operation) { self.stop = stop }
    }
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var drainWaiters: [() -> Void] = []
    private let stoppedWithError: (Error) -> Void
    var pendingCount: Int { sessions.count }

    init(stoppedWithError: @escaping (Error) -> Void = { _ in }) {
        self.stoppedWithError = stoppedWithError
    }

    func start(id: ObjectIdentifier, start: Operation, stop: @escaping Operation,
               completion: @escaping (Error?) -> Void) {
        precondition(sessions[id] == nil, "A capture stream can only start once")
        let session = Session(stop: stop)
        sessions[id] = session
        start { [self, session] error in
            guard sessions[id] === session, session.state == .starting else { return }
            session.state = .running
            // Even a failed start can have allocated a daemon-side session.
            if error != nil { session.stopRequested = true }
            completion(error)
            if session.stopRequested { self.stop(id: id) }
        }
    }

    func stop(id: ObjectIdentifier) {
        guard let session = sessions[id] else { return }
        session.stopRequested = true
        guard session.state == .running else { return }
        session.state = .stopping
        session.stop { [self, session] error in
            guard sessions[id] === session, session.state == .stopping else { return }
            if let error { stoppedWithError(error) }
            sessions.removeValue(forKey: id)
            if sessions.isEmpty {
                let waiters = drainWaiters
                drainWaiters.removeAll()
                waiters.forEach { $0() }
            }
        }
    }

    func stopAll() { Array(sessions.keys).forEach { stop(id: $0) } }

    func whenDrained(_ completion: @escaping () -> Void) {
        if sessions.isEmpty { completion() }
        else { drainWaiters.append(completion) }
    }
}
