import AppKit

// Read-only companion to check-overview-video.py. Records only the native bar,
// Dock overview canvas and Draplet covers, never unrelated window titles.
// Usage: swift scripts/overview-window-probe.swift 24 > windows.log
let duration = CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 24
let started = ProcessInfo.processInfo.systemUptime
var previous = ""
while ProcessInfo.processInfo.systemUptime - started < duration {
    let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let selected = rows.filter { row in
        let owner = row[kCGWindowOwnerName as String] as? String ?? ""
        let layer = row[kCGWindowLayer as String] as? Int ?? 0
        return (owner == "Dock" && layer >= 18) || (owner == "Draplet" && layer == 25) ||
            (layer == 24 && row[kCGWindowName as String] as? String == "Menubar")
    }.map { row -> [String: Any] in
        ["owner": row[kCGWindowOwnerName as String] ?? "", "layer": row[kCGWindowLayer as String] ?? 0,
         "id": row[kCGWindowNumber as String] ?? 0, "alpha": row[kCGWindowAlpha as String] ?? 0,
         "frame": row[kCGWindowBounds as String] ?? [:]]
    }
    let bytes = try! JSONSerialization.data(withJSONObject: selected, options: .sortedKeys)
    let value = String(data: bytes, encoding: .utf8)!
    if value != previous {
        print(String(format: "%.4f", ProcessInfo.processInfo.systemUptime - started), value)
        fflush(stdout)
        previous = value
    }
    Thread.sleep(forTimeInterval: 0.02)
}
