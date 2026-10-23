// Control Center data format referenced from Vorssaint's
// App/MenuBarAllowanceSupport.swift, Copyright (C) 2026 Vorssaint,
// GPL-3.0-or-later. The complete GPL is distributed with Draplet.
import Foundation

enum MenuBarAvailability {
    static func disallowed(in data:Data) -> Set<String> {
        guard let root = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
              let payload = root["trackedApplications"] as? Data,
              let rows = try? PropertyListSerialization.propertyList(from:payload,format:nil) as? [[String:Any]] else { return [] }
        return Set(rows.compactMap { row in
            guard let allowed = row["isAllowed"] as? Bool,!allowed,
                  let location = row["location"] as? [String:Any],let bundle = location["bundle"] as? [String:Any] else { return nil }
            return bundle["_0"] as? String
        })
    }
    static func currentDisallowed() -> Set<String> {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist")
        guard let data = try? Data(contentsOf:path) else { return [] }
        return disallowed(in:data)
    }
}
