// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation

// Reproducible documentation screenshots, with no personal device content.
enum ScreenshotData {
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--demo-content")
        #else
        false
        #endif
    }
    static var containers: [String: [BrowserItem]] {
        let names = [
            ["group.com.example.notes", "group.com.example.photos", "group.com.example.music"],
            ["com.example.Notes", "com.example.Photos", "com.example.Music", "com.example.Reader"],
            ["com.example.ShareExtension", "com.example.Widget"],
            ["com.example.IndexService", "com.example.SyncService"]
        ]
        return Dictionary(uniqueKeysWithValues: zip(ContainerCategory.all, names).map { category, entries in
            (category.path, entries.enumerated().map { index, name in
                BrowserItem(path: category.path + "/Example\(index + 1)", name: name,
                    isDirectory: true, size: 0, modifiedDate: Date(timeIntervalSince1970: 1767225600), itemCount: 3)
            })
        })
    }
    static var events: [BrowserEvent] {
        let source = """
        [
          {"id":"00000000-0000-0000-0000-000000000001","date":789004800,"title":"Ready","detail":"Sample library loaded","kind":"info"},
          {"id":"00000000-0000-0000-0000-000000000002","date":789004802,"title":"Scan complete","detail":"Applications · 4 folders verified · 0 unavailable","kind":"success","duration":0.42},
          {"id":"00000000-0000-0000-0000-000000000003","date":789004804,"title":"Folder opened","detail":"3 items","kind":"success","path":"/Examples/Notes/Documents","duration":0.02},
          {"id":"00000000-0000-0000-0000-000000000004","date":789004806,"title":"Favorite saved","detail":"Documents","kind":"success","path":"/Examples/Notes/Documents"}
        ]
        """
        return (try? JSONDecoder().decode([BrowserEvent].self, from: Data(source.utf8))) ?? []
    }
    static func Directory(_ path: String) -> [BrowserItem] {
        ["Documents", "Library", "tmp"].map {
            BrowserItem(path: path + "/" + $0, name: $0, isDirectory: true, size: 0)
        }
    }
}
