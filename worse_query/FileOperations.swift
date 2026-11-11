// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation
import Darwin

enum CollisionPolicy { case fail, replace, keepBoth }

enum ProgressUnit { case bytes, items, percent }

struct FileProgressUpdate {
    let stage: String
    let completed: Int64
    let total: Int64
    let unit: ProgressUnit
    var displayDetail: String? = nil
    var fraction: Double? { total > 0 ? min(1, Double(completed) / Double(total)) : nil }
    var detail: String {
        if let displayDetail { return displayDetail }
        if unit == .bytes {
            let done = ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)
            let full = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return total > 0 ? "\(done) of \(full)" : done
        }
        if unit == .items { return total > 0 ? "\(completed) of \(total) items" : "\(completed) items found" }
        return total > 0 ? "\(Int(Double(completed) / Double(total) * 100))%" : "Preparing…"
    }
}

enum FileActionError: LocalizedError {
    case exists(String)
    case invalidName
    case protectedLocation
    case invalidCopy
    case invalidMove
    case moveIncomplete(String)
    case folderReplacement
    case demoMode
    var errorDescription: String? {
        switch self {
        case .exists(let name): "An item named “\(name)” already exists."
        case .invalidName: "Use a name without / or null characters. The name cannot be empty or equal to “.” or “..”."
        case .protectedLocation: "Manage the contents of this location instead of the container itself."
        case .invalidCopy: "An item cannot be copied onto itself or into one of its own folders."
        case .invalidMove: "This item is already in the selected folder."
        case .moveIncomplete(let destination): "The new copy is ready at \(destination), but iOS could not fully remove the original. Check its contents before retrying."
        case .folderReplacement: "Folder replacement is not supported. Choose Keep Both instead."
        case .demoMode: "File changes are disabled in sample-data mode."
        }
    }
}

enum FileOperation {
    case newFolder(parent: String, name: String)
    case rename(path: String, name: String)
    case delete(path: String)
    case copy(source: String, directory: String, policy: CollisionPolicy)
    case move(source: String, directory: String, policy: CollisionPolicy)

    var permissionPaths: [String] {
        switch self {
        case .newFolder(let parent, _): [parent]
        case .rename(let path, _), .delete(let path): [URL(fileURLWithPath: path).deletingLastPathComponent().path]
        case .copy(let source, let directory, _), .move(let source, let directory, _):
            [URL(fileURLWithPath: source).deletingLastPathComponent().path, directory]
        }
    }
    var title: String {
        switch self {
        case .newFolder: "Folder created"
        case .rename: "Item renamed"
        case .delete: "Item deleted"
        case .copy(_, _, let policy): policy == .replace ? "File replaced" : "Item copied"
        case .move: "Item moved"
        }
    }
    var actionTitle: String {
        switch self {
        case .newFolder: "Creating folder"
        case .rename: "Renaming item"
        case .delete: "Deleting item"
        case .copy(_, _, let policy): policy == .replace ? "Replacing file" : "Copying item"
        case .move: "Moving item"
        }
    }
    var symbol: String {
        switch self {
        case .newFolder: "folder.badge.plus"
        case .rename: "pencil"
        case .delete: "trash"
        case .copy(_, _, let policy): policy == .replace ? "arrow.triangle.2.circlepath" : "doc.on.doc"
        case .move: "folder.fill"
        }
    }
}

struct FileOperations {
    private static let files = FileManager.default

    static func Apply(_ operation: FileOperation,
                      progress: (FileProgressUpdate) -> Void = { _ in }) throws -> URL {
        switch operation {
        case .newFolder(let parent, let name):
            let target = try Child(parent, name: name)
            guard !Exists(target) else { throw FileActionError.exists(target.lastPathComponent) }
            try files.createDirectory(at: target, withIntermediateDirectories: false)
            return target
        case .rename(let path, let name):
            let source = URL(fileURLWithPath: path).standardizedFileURL
            try ValidateMutable(source)
            let target = try Child(source.deletingLastPathComponent().path, name: name)
            if target == source { return source }
            guard !Exists(target) else { throw FileActionError.exists(target.lastPathComponent) }
            try files.moveItem(at: source, to: target)
            return target
        case .delete(let path):
            let source = URL(fileURLWithPath: path).standardizedFileURL
            try ValidateMutable(source)
            var entries: [TreeEntry] = []
            try Gather(source, relative: "", entries: &entries) { count in
                progress(.init(stage: "Preparing deletion", completed: Int64(count), total: 0, unit: .items))
            }
            let total = Int64(entries.count)
            progress(.init(stage: "Deleting", completed: 0, total: total, unit: .items))
            for (index, entry) in entries.enumerated() {
                try files.removeItem(at: entry.url)
                progress(.init(stage: "Deleting", completed: Int64(index + 1), total: total, unit: .items))
            }
            return source
        case .copy(let path, let directory, let policy):
            let source = URL(fileURLWithPath: path).standardizedFileURL
            var target = try Child(directory, name: source.lastPathComponent)
            let resolvedSource = source.resolvingSymlinksInPath().path
            // Resolve the existing parent, not a destination leaf that does not exist yet.
            let resolvedParent = target.deletingLastPathComponent().resolvingSymlinksInPath().path
            if resolvedParent == resolvedSource || resolvedParent.hasPrefix(resolvedSource + "/") {
                throw FileActionError.invalidCopy
            }
            if Exists(target) {
                switch policy {
                case .fail: throw FileActionError.exists(target.lastPathComponent)
                case .keepBoth: target = Unique(target)
                case .replace:
                    guard source.path != target.path else { throw FileActionError.invalidCopy }
                    let sourceType = try files.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
                    let targetType = try files.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType
                    guard sourceType != .typeDirectory && targetType != .typeDirectory else { throw FileActionError.folderReplacement }
                    // A staged file in the same directory permits an atomic replacement.
                    let stage = target.deletingLastPathComponent().appendingPathComponent(".fileslab-\(UUID().uuidString)")
                    defer { try? files.removeItem(at: stage) }
                    try CopyToStage(source, stage, progress: progress)
                    progress(.init(stage: "Replacing file", completed: 1, total: 1, unit: .items))
                    guard Darwin.rename(stage.path, target.path) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    return target
                }
            }
            guard source.path != target.path else { throw FileActionError.invalidCopy }
            let stage = target.deletingLastPathComponent().appendingPathComponent(".fileslab-\(UUID().uuidString)")
            defer { try? files.removeItem(at: stage) }
            try CopyToStage(source, stage, progress: progress)
            do { try files.moveItem(at: stage, to: target) }
            catch {
                if Exists(target) { throw FileActionError.exists(target.lastPathComponent) }
                throw error
            }
            return target
        case .move(let path, let directory, let policy):
            let source = URL(fileURLWithPath: path).standardizedFileURL
            try ValidateMutable(source)
            guard source.deletingLastPathComponent().resolvingSymlinksInPath().path !=
                    URL(fileURLWithPath: directory).resolvingSymlinksInPath().path else {
                throw FileActionError.invalidMove
            }
            let target = try Apply(.copy(source: source.path, directory: directory, policy: policy)) { update in
                let amount = Int64((Double(update.fraction ?? 0) * 850).rounded())
                progress(.init(stage: "Moving", completed: amount, total: 1000,
                               unit: .percent, displayDetail: "Copying: \(update.detail)"))
            }
            do {
                _ = try Apply(.delete(path: source.path)) { update in
                    let amount = 850 + Int64((Double(update.fraction ?? 0) * 150).rounded())
                    progress(.init(stage: "Moving", completed: amount, total: 1000,
                                   unit: .percent, displayDetail: "Removing original: \(update.detail)"))
                }
            } catch { throw FileActionError.moveIncomplete(target.path) }
            return target
        }
    }

    private struct TreeEntry {
        let url: URL
        let relative: String
        let isDirectory: Bool
        let isLink: Bool
        let size: Int64
    }

    private static func Gather(_ url: URL, relative: String, entries: inout [TreeEntry],
                               progress: (Int) -> Void) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        let isLink = values.isSymbolicLink ?? false
        let isDirectory = (values.isDirectory ?? false) && !isLink
        if isDirectory {
            let children = try files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            for child in children {
                let childRelative = relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent
                try Gather(child, relative: childRelative, entries: &entries, progress: progress)
            }
        }
        entries.append(.init(url: url, relative: relative, isDirectory: isDirectory,
                             isLink: isLink, size: isDirectory ? 0 : Int64(values.fileSize ?? 0)))
        progress(entries.count)
    }

    private static func CopyToStage(_ source: URL, _ stage: URL,
                                    progress: (FileProgressUpdate) -> Void) throws {
        var entries: [TreeEntry] = []
        try Gather(source, relative: "", entries: &entries) { count in
            progress(.init(stage: "Preparing copy", completed: Int64(count), total: 0, unit: .items))
        }
        var totalBytes = entries.reduce(Int64(0)) { $0 + ($1.isLink ? 0 : $1.size) }
        let totalItems = Int64(entries.count)
        var copiedBytes: Int64 = 0
        var copiedItems: Int64 = 0
        var unit: ProgressUnit = totalBytes > 0 ? .bytes : .items
        func report() {
            progress(.init(stage: "Copying", completed: unit == .bytes ? copiedBytes : copiedItems,
                           total: unit == .bytes ? totalBytes : totalItems, unit: unit))
        }
        report()
        for entry in entries.reversed() {
            let destination = entry.relative.isEmpty ? stage : stage.appendingPathComponent(entry.relative)
            if entry.isDirectory {
                try files.createDirectory(at: destination, withIntermediateDirectories: false)
            } else if entry.isLink {
                try files.copyItem(at: entry.url, to: destination)
            } else {
                try CopyFile(entry.url, destination, size: { actualSize in
                    if actualSize != entry.size {
                        totalBytes += actualSize - entry.size
                        unit = totalBytes > 0 ? .bytes : .items
                        report()
                    }
                }) { bytes in
                    copiedBytes += bytes
                    report()
                }
            }
            copiedItems += 1
            report()
        }
    }

    private static func CopyFile(_ source: URL, _ destination: URL,
                                 size: (Int64) -> Void,
                                 progress: (Int64) -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var coordinated = false
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            coordinated = true
            do {
                guard files.createFile(atPath: destination.path, contents: nil) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                let input = try FileHandle(forReadingFrom: readableURL)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? input.close(); try? output.close() }
                if let actualSize = try? input.seekToEnd() {
                    try input.seek(toOffset: 0)
                    size(Int64(actualSize))
                }
                while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
                    try output.write(contentsOf: data)
                    progress(Int64(data.count))
                }
                try output.synchronize()
                let attributes = try files.attributesOfItem(atPath: source.path)
                var preserved: [FileAttributeKey: Any] = [:]
                if let value = attributes[.posixPermissions] { preserved[.posixPermissions] = value }
                if let value = attributes[.modificationDate] { preserved[.modificationDate] = value }
                try? files.setAttributes(preserved, ofItemAtPath: destination.path)
            } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
        guard coordinated else { throw CocoaError(.fileReadUnknown) }
    }

    private static func Child(_ directory: String, name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileActionError.invalidName
        }
        return URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).standardizedFileURL
    }

    private static func Exists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func Unique(_ original: URL) -> URL {
        let parent = original.deletingLastPathComponent()
        let directory = (try? files.attributesOfItem(atPath: original.path)[.type] as? FileAttributeType) == .typeDirectory
        let ext = directory ? "" : original.pathExtension
        let stem = ext.isEmpty ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let candidate = parent.appendingPathComponent(stem + suffix + (ext.isEmpty ? "" : "." + ext))
            if !Exists(candidate) { return candidate }
            index += 1
        }
    }

    private static func ValidateMutable(_ source: URL) throws {
        let path = source.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(source.lastPathComponent).path
        let fixed = ["/", "/private", "/var", "/private/var", "/var/mobile", "/private/var/mobile"]
        guard !fixed.contains(path) else { throw FileActionError.protectedLocation }
        for category in ContainerCategory.all {
            if path == category.path { throw FileActionError.protectedLocation }
            if path.hasPrefix(category.path + "/") && !path.dropFirst(category.path.count + 1).contains("/") {
                throw FileActionError.protectedLocation
            }
        }
    }

    static func Verify(in parent: URL? = nil) throws -> [String] {
        let root = (parent ?? files.temporaryDirectory).appendingPathComponent("FilesLab-Operations-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        print("File operation test: create folders and copy file")
        let sourceFolder = try Apply(.newFolder(parent: root.path, name: "Source"))
        let targetFolder = try Apply(.newFolder(parent: root.path, name: "Target"))
        let source = sourceFolder.appendingPathComponent("Sample.txt")
        try Data("new content".utf8).write(to: source)
        let copied = try Apply(.copy(source: source.path, directory: targetFolder.path, policy: .fail))
        guard try Data(contentsOf: copied) == Data(contentsOf: source) else { throw CocoaError(.fileReadCorruptFile) }
        do {
            _ = try Apply(.copy(source: source.path, directory: targetFolder.path, policy: .fail))
            throw CocoaError(.fileWriteUnknown)
        } catch FileActionError.exists { }
        print("File operation test: replace, duplicate, rename, delete")
        try Data("old content".utf8).write(to: copied)
        _ = try Apply(.copy(source: source.path, directory: targetFolder.path, policy: .replace))
        guard try Data(contentsOf: copied) == Data("new content".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let duplicate = try Apply(.copy(source: source.path, directory: targetFolder.path, policy: .keepBoth))
        guard duplicate != copied, Exists(duplicate) else { throw CocoaError(.fileWriteUnknown) }
        let renamed = try Apply(.rename(path: duplicate.path, name: "Renamed.txt"))
        guard !Exists(duplicate), Exists(renamed) else { throw CocoaError(.fileWriteUnknown) }
        _ = try Apply(.delete(path: renamed.path))
        guard !Exists(renamed) else { throw CocoaError(.fileWriteUnknown) }
        print("File operation test: folder copy and failure preservation")
        let folderCopy = try Apply(.copy(source: sourceFolder.path, directory: targetFolder.path, policy: .fail))
        guard Exists(folderCopy.appendingPathComponent("Sample.txt")) else { throw CocoaError(.fileWriteUnknown) }
        _ = try Apply(.delete(path: folderCopy.path))
        do {
            _ = try Apply(.newFolder(parent: root.path, name: "../invalid"))
            throw CocoaError(.fileWriteUnknown)
        } catch FileActionError.invalidName { }
        let missing = sourceFolder.appendingPathComponent("Missing.txt")
        let existing = targetFolder.appendingPathComponent("Missing.txt")
        try Data("preserve me".utf8).write(to: existing)
        var rejectedMissingSource = false
        do { _ = try Apply(.copy(source: missing.path, directory: targetFolder.path, policy: .replace)) }
        catch { rejectedMissingSource = true }
        guard rejectedMissingSource, try Data(contentsOf: existing) == Data("preserve me".utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let conflictingFolder = try Apply(.newFolder(parent: targetFolder.path, name: sourceFolder.lastPathComponent))
        do {
            _ = try Apply(.copy(source: sourceFolder.path, directory: targetFolder.path, policy: .replace))
            throw CocoaError(.fileWriteUnknown)
        } catch FileActionError.folderReplacement { }
        guard Exists(conflictingFolder), Exists(source) else { throw CocoaError(.fileWriteUnknown) }
        print("File operation test: reject recursive copy")
        do {
            _ = try Apply(.copy(source: sourceFolder.path, directory: sourceFolder.path, policy: .fail))
            throw CocoaError(.fileWriteUnknown)
        } catch FileActionError.invalidCopy { }
        let childFolder = try Apply(.newFolder(parent: sourceFolder.path, name: "Child"))
        do {
            _ = try Apply(.copy(source: sourceFolder.path, directory: childFolder.path, policy: .fail))
            throw CocoaError(.fileWriteUnknown)
        } catch FileActionError.invalidCopy { }
        print("File operation test: symlink deletion preserves target")
        let link = root.appendingPathComponent("Alias")
        try files.createSymbolicLink(at: link, withDestinationURL: sourceFolder)
        _ = try Apply(.delete(path: link.path))
        guard Exists(sourceFolder) else { throw CocoaError(.fileWriteUnknown) }
        let large = sourceFolder.appendingPathComponent("Large.bin")
        try Data(repeating: 0xA5, count: 2_500_000).write(to: large)
        var copyProgress: [FileProgressUpdate] = []
        let largeCopy = try Apply(.copy(source: large.path, directory: targetFolder.path, policy: .fail)) {
            copyProgress.append($0)
        }
        guard try Data(contentsOf: largeCopy) == Data(contentsOf: large),
              copyProgress.contains(where: { $0.stage == "Copying" && $0.unit == .bytes && $0.completed > 0 && $0.completed < $0.total }),
              copyProgress.last(where: { $0.stage == "Copying" })?.fraction == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var moveProgress: [FileProgressUpdate] = []
        let movedLarge = try Apply(.move(source: large.path, directory: targetFolder.path, policy: .keepBoth)) {
            moveProgress.append($0)
        }
        guard !Exists(large), Exists(largeCopy),
              try Data(contentsOf: movedLarge) == Data(contentsOf: largeCopy),
              moveProgress.last?.stage == "Moving", moveProgress.last?.fraction == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try Data("moved content".utf8).write(to: source)
        let movedReplacement = try Apply(.move(source: source.path, directory: targetFolder.path, policy: .replace))
        guard !Exists(source), try Data(contentsOf: movedReplacement) == Data("moved content".utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let moveFolder = try Apply(.newFolder(parent: root.path, name: "Move Folder"))
        try Data("nested".utf8).write(to: moveFolder.appendingPathComponent("Content.txt"))
        let movedFolder = try Apply(.move(source: moveFolder.path, directory: targetFolder.path, policy: .fail))
        guard !Exists(moveFolder), Exists(movedFolder.appendingPathComponent("Content.txt")) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let progressFolder = try Apply(.newFolder(parent: root.path, name: "Progress"))
        try Data("one".utf8).write(to: progressFolder.appendingPathComponent("One.txt"))
        let nested = try Apply(.newFolder(parent: progressFolder.path, name: "Nested"))
        try Data("two".utf8).write(to: nested.appendingPathComponent("Two.txt"))
        var deleteProgress: [FileProgressUpdate] = []
        _ = try Apply(.delete(path: progressFolder.path)) { deleteProgress.append($0) }
        guard !Exists(progressFolder),
              deleteProgress.last?.stage == "Deleting",
              deleteProgress.last?.completed == deleteProgress.last?.total,
              (deleteProgress.last?.total ?? 0) >= 4 else {
            throw CocoaError(.fileWriteUnknown)
        }
        try files.removeItem(at: root)
        guard !Exists(root) else { throw CocoaError(.fileWriteUnknown) }
        return ["Create, streamed copy with byte progress, move with progress, safe replacement, keep both, rename, counted folder deletion, invalid-name rejection, failed-replacement preservation, recursive-copy rejection, and symlink deletion passed."]
    }
}
