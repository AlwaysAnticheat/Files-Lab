// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation
import Darwin

enum CollisionPolicy { case fail, replace, keepBoth }

enum FileActionError: LocalizedError {
    case exists(String)
    case invalidName
    case protectedLocation
    case invalidCopy
    case folderReplacement
    case demoMode
    var errorDescription: String? {
        switch self {
        case .exists(let name): "An item named “\(name)” already exists."
        case .invalidName: "Use a name without / or null characters. The name cannot be empty or equal to “.” or “..”."
        case .protectedLocation: "Manage the contents of this location instead of the container itself."
        case .invalidCopy: "An item cannot be copied onto itself or into one of its own folders."
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

    var permissionPaths: [String] {
        switch self {
        case .newFolder(let parent, _): [parent]
        case .rename(let path, _), .delete(let path): [URL(fileURLWithPath: path).deletingLastPathComponent().path]
        case .copy(let source, let directory, _): [URL(fileURLWithPath: source).deletingLastPathComponent().path, directory]
        }
    }
    var title: String {
        switch self {
        case .newFolder: "Folder created"
        case .rename: "Item renamed"
        case .delete: "Item deleted"
        case .copy: "Item copied"
        }
    }
}

struct FileOperations {
    private static let files = FileManager.default

    static func Apply(_ operation: FileOperation) throws -> URL {
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
            try files.removeItem(at: source)
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
                    try files.copyItem(at: source, to: stage)
                    guard Darwin.rename(stage.path, target.path) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    return target
                }
            }
            guard source.path != target.path else { throw FileActionError.invalidCopy }
            let stage = target.deletingLastPathComponent().appendingPathComponent(".fileslab-\(UUID().uuidString)")
            defer { try? files.removeItem(at: stage) }
            try files.copyItem(at: source, to: stage)
            do { try files.moveItem(at: stage, to: target) }
            catch {
                if Exists(target) { throw FileActionError.exists(target.lastPathComponent) }
                throw error
            }
            return target
        }
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
        try files.removeItem(at: root)
        guard !Exists(root) else { throw CocoaError(.fileWriteUnknown) }
        return ["Create, copy, collision handling, atomic replace, keep both, rename, delete, folder copy, invalid-name rejection, failed-replacement preservation, recursive-copy rejection, and symlink deletion passed."]
    }
}
