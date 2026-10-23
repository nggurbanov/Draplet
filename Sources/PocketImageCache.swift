import AppKit
import CryptoKit

// Expiry requests an idle refresh. A failed refresh never removes last-good ink.
final class PocketImageCache {
    static let shared = PocketImageCache()
    private struct Entry: Codable {
        let key: String
        var png: Data?
        var width = 0.0, height = 0.0
        var template = false
        var pid: Int32 = 0
        var scale = 0.0
        var captured: Date?
        var failures = 0
        var retryAfter: Date?
        var foregroundRetry: Bool? = false
    }
    private let directory: URL
    private let disk = DispatchQueue(label:"Draplet.PocketImageCache",qos:.utility)
    private var entries: [String:Entry] = [:]
    private var images: [String:NSImage] = [:]
    private var stale = Set<String>()
    private(set) var diskHits = 0
    private(set) var successes = 0
    init(directory: URL = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
        .appendingPathComponent("com.tyrell.Draplet/Pocket-v1",isDirectory:true)) { self.directory = directory }
    private func url(_ key:String) -> URL {
        let name = SHA256.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
        return directory.appendingPathComponent(name+".plist")
    }
    private func entry(_ key:String) -> Entry {
        if let e = entries[key] { return e }
        let path = url(key)
        if let size = try? path.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 2_000_000,
           let data = try? Data(contentsOf:path), let e = try? PropertyListDecoder().decode(Entry.self,from:data), e.key == key {
            entries[key] = e;diskHits += 1;return e
        }
        let e = Entry(key:key);entries[key] = e;return e
    }
    func image(_ key:String) -> NSImage? {
        if let image = images[key] { return image }
        let e = entry(key)
        guard let data = e.png,e.width > 0,e.height > 0,e.width <= 4096,e.height <= 256,
              let image = NSImage(data:data) else { return nil }
        image.size = CGSize(width:e.width,height:e.height);image.isTemplate = e.template
        images[key] = image;return image
    }
    func needsRefresh(_ key:String,pid:pid_t,scale:CGFloat,now:Date = Date(),foreground:Bool = false) -> Bool {
        let e = entry(key)
        if foreground && e.foregroundRetry == true { return true }
        if e.pid == pid,let retry = e.retryAfter,retry > now { return false }
        return e.pid != pid || e.scale != Double(scale) || stale.contains(key)
            || (e.captured.map { now.timeIntervalSince($0) >= 120 } ?? true)
    }
    func failed(_ key:String,pid:pid_t,now:Date = Date(),background:Bool = false) {
        var e = entry(key);e.failures = e.pid == pid ? e.failures+1 : 1;e.pid = pid
        e.foregroundRetry = background && e.png == nil
        let delays:[Double] = [30,120,600,3600]
        e.retryAfter = now.addingTimeInterval(delays[min(delays.count-1,e.failures-1)])
        entries[key] = e;persist(e)
    }
    func succeeded(_ image:NSImage,key:String,pid:pid_t,scale:CGFloat,now:Date = Date()) {
        var rect = CGRect(origin:.zero,size:image.size)
        guard let cg = image.cgImage(forProposedRect:&rect,context:nil,hints:nil),
              let png = NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else { return }
        var e = Entry(key:key);e.png = png;e.width = image.size.width;e.height = image.size.height
        e.template = image.isTemplate;e.pid = pid;e.scale = Double(scale);e.captured = now
        entries[key] = e;images[key] = image;stale.remove(key);successes += 1;persist(e)
    }
    func unavailable(_ key:String) -> Bool { image(key) == nil && entry(key).failures > 0 && entry(key).foregroundRetry != true }
    func requestRefresh(_ keys:[String]) {
        for key in keys { var e = entry(key);e.retryAfter = nil;e.failures = 0;entries[key] = e;stale.insert(key) }
    }
    func appearanceChanged() { stale.formUnion(entries.keys) }
    private func persist(_ entry:Entry) {
        let encoder = PropertyListEncoder();encoder.outputFormat = .binary
        guard let data = try? encoder.encode(entry) else { return }
        let directory = directory,path = url(entry.key)
        disk.async {
            try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try? data.write(to:path,options:.atomic)
            let files = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])) ?? []
            if files.count > 128 {
                let ordered = files.filter { $0.pathExtension == "plist" }.sorted {
                    ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                        < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
                for file in ordered.prefix(max(0,ordered.count-128)) { try? FileManager.default.removeItem(at:file) }
            }
        }
        if entries.count > 128,let oldest = entries.keys.first(where:{ $0 != entry.key }) {
            entries[oldest] = nil;images[oldest] = nil;stale.remove(oldest)
        }
    }
    func flush() { disk.sync {} }
}
