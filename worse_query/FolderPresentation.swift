// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation

enum FolderLayout: String, CaseIterable {
    case icons, list
}

enum FolderSort: String, CaseIterable {
    case name, kind, date, size
    var label: String { rawValue.capitalized }
}

struct FolderOrdering {
    static func Arrange(_ items: [BrowserItem], search: String, sort: FolderSort,
                        ascending: Bool, foldersFirst: Bool, showHidden: Bool) -> [BrowserItem] {
        items.filter {
            (showHidden || !$0.name.hasPrefix(".")) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted { left, right in
            if foldersFirst && left.isDirectory != right.isDirectory { return left.isDirectory }
            let comparison: ComparisonResult
            switch sort {
            case .name:
                comparison = left.name.localizedStandardCompare(right.name)
            case .kind:
                let leftKind = left.isDirectory ? "Folder" : left.url.pathExtension.lowercased()
                let rightKind = right.isDirectory ? "Folder" : right.url.pathExtension.lowercased()
                comparison = leftKind.localizedStandardCompare(rightKind)
            case .date:
                // Keep unknown dates last in either direction.
                if (left.modifiedDate == nil) != (right.modifiedDate == nil) { return left.modifiedDate != nil }
                comparison = Compare(left.modifiedDate ?? .distantPast, right.modifiedDate ?? .distantPast)
            case .size:
                let leftSize = left.isDirectory ? Int64(left.itemCount ?? 0) : left.size
                let rightSize = right.isDirectory ? Int64(right.itemCount ?? 0) : right.size
                comparison = Compare(leftSize, rightSize)
            }
            if comparison == .orderedSame {
                let nameOrder = left.name.localizedStandardCompare(right.name)
                if nameOrder == .orderedSame { return left.path < right.path }
                return nameOrder == .orderedAscending
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func Compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    }

    static func Verify() -> Bool {
        let items = [
            BrowserItem(path: "/b.txt", name: "B.txt", isDirectory: false, size: 10, modifiedDate: Date(timeIntervalSince1970: 20)),
            BrowserItem(path: "/a.png", name: "A.png", isDirectory: false, size: 30, modifiedDate: Date(timeIntervalSince1970: 10)),
            BrowserItem(path: "/folder", name: "Folder", isDirectory: true, size: 0, itemCount: 4),
            BrowserItem(path: "/hidden", name: ".hidden", isDirectory: false, size: 2)
        ]
        func ordered(_ sort: FolderSort, ascending: Bool = true, first: Bool = false, hidden: Bool = false, search: String = "") -> [String] {
            Arrange(items, search: search, sort: sort, ascending: ascending, foldersFirst: first, showHidden: hidden).map(\.path)
        }
        return ordered(.name) == ["/a.png", "/b.txt", "/folder"] &&
            ordered(.name, ascending: false) == ["/folder", "/b.txt", "/a.png"] &&
            ordered(.size) == ["/folder", "/b.txt", "/a.png"] &&
            ordered(.date) == ["/a.png", "/b.txt", "/folder"] &&
            ordered(.kind) == ["/folder", "/a.png", "/b.txt"] &&
            ordered(.name, first: true).first == "/folder" &&
            ordered(.name, hidden: true).count == 4 &&
            ordered(.name, search: "B.TXT") == ["/b.txt"]
    }
}
