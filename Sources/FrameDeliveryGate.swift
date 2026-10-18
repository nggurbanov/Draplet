// Confined to the serial capture queue. Keep at most one converted frame waiting
// for main, even when Settings, AX or WindowServer momentarily stalls the UI.
struct FrameDeliveryGate {
    private var serial = 0
    private var pending: Int?
    mutating func begin() -> Int? {
        guard pending == nil else { return nil }
        serial += 1; pending = serial
        return serial
    }
    mutating func finish(_ token: Int) { if pending == token { pending = nil } }
    mutating func reset() { serial += 1; pending = nil }
}
