import Foundation

// Pocket order is independent of the physical menu bar. Keys identify native
// status items across publisher restarts, including siblings from one app.
enum PocketItemOrder {
    static func unique(_ keys:[String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func ordered(_ visible:[String], saved:[String]) -> [String] {
        let available = Set(visible)
        return unique(saved.filter { available.contains($0) } + visible)
    }
    static func moving(_ source:String, relativeTo target:String, after:Bool,
                       visible:[String], saved:[String]) -> [String]? {
        guard source != target,visible.contains(source),visible.contains(target) else { return nil }
        var result = unique(saved + visible).filter { $0 != source }
        guard let index = result.firstIndex(of:target) else { return nil }
        result.insert(source,at:index + (after ? 1 : 0))
        return Array(result.prefix(1024))
    }
}
