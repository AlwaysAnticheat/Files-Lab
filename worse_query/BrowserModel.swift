// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation
import Combine
import Darwin

struct BrowserItem: Identifiable, Hashable, Codable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    var modifiedDate: Date? = nil
    var itemCount: Int? = nil
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }
}

struct ContainerCategory: Identifiable, Hashable {
    let name: String
    let path: String
    let symbol: String
    var id: String { path }
    static let all: [ContainerCategory] = [
        .init(name: "App Groups", path: "/private/var/mobile/Containers/Shared/AppGroup", symbol: "square.stack.3d.up.fill"),
        .init(name: "Applications", path: "/private/var/mobile/Containers/Data/Application", symbol: "square.grid.2x2"),
        .init(name: "App Extensions", path: "/private/var/mobile/Containers/Data/PluginKitPlugin", symbol: "puzzlepiece.extension.fill"),
        .init(name: "Internal Daemons", path: "/private/var/mobile/Containers/Data/InternalDaemon", symbol: "gearshape.2.fill")
    ]
}

enum EventKind: String, Codable {
    case info, success, error
}

struct BrowserEvent: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let kind: EventKind
    let path: String?
    let duration: TimeInterval?
    var message: String { detail.isEmpty ? title : "\(title): \(detail)" }
    var isError: Bool { kind == .error }

    init(_ title: String, detail: String = "", kind: EventKind = .info,
         path: String? = nil, duration: TimeInterval? = nil) {
        id = UUID(); date = Date(); self.title = title; self.detail = detail
        self.kind = kind; self.path = path; self.duration = duration
    }
}

@MainActor
final class ActivityLog: ObservableObject {
    @Published private(set) var events: [BrowserEvent] = []
    private let queue = DispatchQueue(label: "FilesLab.ActivityPersistence", qos: .utility)
    private var pendingWrite: DispatchWorkItem?
    private let file: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("Activity.json")
        if ScreenshotData.enabled { events = ScreenshotData.events; return }
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([BrowserEvent].self, from: data) {
            events = Array(saved.suffix(500))
        }
    }

    func Append(_ event: BrowserEvent) {
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
        Save()
    }

    func Clear() {
        events.removeAll()
        Save()
    }

    func Export(_ entries: [BrowserEvent]) -> String {
        entries.map { event in
            var line = "\(event.date.ISO8601Format()) [\(event.kind.rawValue.uppercased())] \(event.message)"
            if let path = event.path { line += "\n  Path: \(path)" }
            if let duration = event.duration { line += String(format: "\n  Duration: %.2f s", duration) }
            return line
        }.joined(separator: "\n\n")
    }

    func Flush() { Save(delay: 0) }

    private func Save(delay: TimeInterval = 0.5) {
        guard !ScreenshotData.enabled else { return }
        pendingWrite?.cancel()
        let snapshot = events
        let destination = file
        let write = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: destination, options: .atomic)
            }
        }
        pendingWrite = write
        queue.asyncAfter(deadline: .now() + delay, execute: write)
    }
}

private struct AccessFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Every exploit call uses the same App Group cache path, so serialize those calls.
final class FileAccess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FilesLab.Access", qos: .userInitiated)
    private var handles: [String: Int64] = [:]
    private let group = Bundle.main.object(forInfoDictionaryKey: "FilesLabAppGroup") as? String ?? "group.com.example.FilesLab"
    private let files = FileManager.default

    func Discover(_ category: ContainerCategory) async throws -> ([BrowserItem], [BrowserEvent]) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.DiscoverSync(category)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func List(_ path: String, root: String?) async throws -> [BrowserItem] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if let root { try self.Acquire(root) }
                    continuation.resume(returning: try self.ReadDirectory(path))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func ReadDirectory(_ path: String) throws -> [BrowserItem] {
        let urls = try files.contentsOfDirectory(at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey, .contentModificationDateKey])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey, .contentModificationDateKey])
            var directory = ObjCBool(values?.isDirectory ?? false)
            var path = url.path
            if values?.isSymbolicLink == true {
                _ = files.fileExists(atPath: url.path, isDirectory: &directory)
                if directory.boolValue { path = url.resolvingSymlinksInPath().path }
            }
            return BrowserItem(path: path, name: url.lastPathComponent,
                isDirectory: directory.boolValue, size: Int64(values?.fileSize ?? 0), modifiedDate: values?.contentModificationDate)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func Acquire(_ root: String) throws {
        guard handles[root] == nil else { return }
        let alternate = root.contains("/Containers/Shared/AppGroup/") && ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
        let handle = worse_query(root, group, alternate, false)
        guard handle >= 0 else {
            throw AccessFailure(message: "iOS refused access to this location (code \(handle)).")
        }
        handles[root] = handle
    }

    private func DiscoverSync(_ category: ContainerCategory) throws -> ([BrowserItem], [BrowserEvent]) {
        let baseline = files.temporaryDirectory.appendingPathComponent(".baseline_\(UUID().uuidString)")
        try Data("baseline".utf8).write(to: baseline)
        defer { try? files.removeItem(at: baseline) }
        var info = stat()
        guard stat(baseline.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard let paths = pathleak(category.path, info.st_ino) else {
            throw AccessFailure(message: "iOS did not allow discovery at this location.")
        }
        var found: [BrowserItem] = []
        var errors = 0
        for path in paths {
            let wasHeld = handles[path] != nil
            do {
                try Acquire(path)
                let children = try ReadDirectory(path)
                var buffer = [CChar](repeating: 0, count: 1024)
                let length = getxattr(path, "com.apple.containermanager.identifier", &buffer, 1023, 0, 0)
                let name = length > 0 ? String(cString: buffer) : URL(fileURLWithPath: path).lastPathComponent
                let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey])
                found.append(.init(path: path, name: name, isDirectory: true, size: 0,
                    modifiedDate: values?.contentModificationDate, itemCount: children.count))
            } catch { errors += 1 }
            if !wasHeld, let handle = handles.removeValue(forKey: path) { worse_query_release(handle) }
        }
        found.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (found, [BrowserEvent("Scan complete", detail: "\(category.name) · \(found.count) folders verified · \(errors) unavailable", kind: .success)])
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var containers: [String: [BrowserItem]] = [:]
    @Published var loading: Set<String> = []
    @Published var errors: [String: String] = [:]
    let activity = ActivityLog()
    @Published var favorites: [BrowserItem] = []
    private let access = FileAccess()
    private var directoryCache: [String: [BrowserItem]] = [:]
    private var directoryCacheOrder: [String] = []
    private let defaults = UserDefaults.standard

    init() {
        if ScreenshotData.enabled { containers = ScreenshotData.containers; return }
        if let data = defaults.data(forKey: "ContainerCache"),
           let cache = try? JSONDecoder().decode([String: [BrowserItem]].self, from: data) {
            containers = cache.mapValues { items in
                items.map { old in
                    var item = old
                    if item.itemCount == nil { item.itemCount = Int(item.size); }
                    return item
                }
            }
        }
        if let data = defaults.data(forKey: "Favorites"),
           let saved = try? JSONDecoder().decode([BrowserItem].self, from: data) { favorites = saved }
        Log("Ready", detail: "\(containers.values.reduce(0) { $0 + $1.count }) cached container folders")
    }

    func Log(_ title: String, detail: String = "", kind: EventKind = .info,
             path: String? = nil, duration: TimeInterval? = nil, error: Bool = false) {
        let event = BrowserEvent(title, detail: detail, kind: error ? .error : kind,
                                 path: path, duration: duration)
        print("Files Lab: \(event.message)\(path.map { " · " + $0 } ?? "")")
        activity.Append(event)
    }

    func Discover(_ category: ContainerCategory, force: Bool = false) async {
        if ScreenshotData.enabled { return }
        guard !loading.contains(category.path) else { return }
        guard force || containers[category.path] == nil else { return }
        loading.insert(category.path); errors[category.path] = nil
        let started = Date()
        Log("Finding folders", detail: category.name, path: category.path)
        defer { loading.remove(category.path) }
        do {
            let (items, messages) = try await access.Discover(category)
            containers[category.path] = items
            messages.forEach { Log($0.title, detail: $0.detail, kind: $0.kind,
                                    path: category.path, duration: Date().timeIntervalSince(started)) }
            if let data = try? JSONEncoder().encode(containers) { defaults.set(data, forKey: "ContainerCache") }
        } catch {
            errors[category.path] = error.localizedDescription
            Log("Scan failed", detail: error.localizedDescription, path: category.path, error: true)
        }
    }

    func Directory(_ path: String, root: String?, refresh: Bool = false) async throws -> [BrowserItem] {
        if ScreenshotData.enabled { return ScreenshotData.Directory(path) }
        if !refresh, let cached = directoryCache[path] { return cached }
        let started = Date()
        do {
            let items = try await access.List(path, root: root)
            directoryCache[path] = items
            directoryCacheOrder.removeAll { $0 == path }
            directoryCacheOrder.append(path)
            while directoryCacheOrder.count > 80 {
                directoryCache.removeValue(forKey: directoryCacheOrder.removeFirst())
            }
            Log("Folder opened", detail: "\(items.count) \(items.count == 1 ? "item" : "items")", kind: .success,
                path: path, duration: Date().timeIntervalSince(started))
            return items
        } catch {
            Log("Folder unavailable", detail: error.localizedDescription, path: path, error: true)
            throw error
        }
    }

    func ToggleFavorite(_ item: BrowserItem) {
        if let index = favorites.firstIndex(where: { $0.path == item.path }) {
            favorites.remove(at: index)
            Log("Favorite removed", detail: item.name, path: item.path)
        } else {
            favorites.append(item)
            Log("Favorite saved", detail: item.name, kind: .success, path: item.path)
        }
        if !ScreenshotData.enabled, let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: "Favorites") }
    }

    func Root(for path: String) -> String? {
        for category in ContainerCategory.all where path.hasPrefix(category.path + "/") {
            let remaining = path.dropFirst(category.path.count + 1)
            guard let component = remaining.split(separator: "/").first else { continue }
            return category.path + "/" + component
        }
        return nil
    }

    func Verify() async {
        guard !ScreenshotData.enabled else {
            Log("Verification skipped", detail: "Sample-data mode does not test real device access")
            return
        }
        for category in ContainerCategory.all { await Discover(category, force: true) }
        do { _ = try await Directory("/", root: nil, refresh: true) }
        catch { Log("File System root cannot be listed on this device.") }
        var checked = false
        for item in containers[ContainerCategory.all[0].path] ?? [] {
            do {
                let root = try await Directory(item.path, root: item.path, refresh: true)
                guard let child = root.first(where: { $0.isDirectory }) else { continue }
                _ = try await Directory(child.path, root: item.path, refresh: true)
                let returned = try await Directory(item.path, root: item.path, refresh: true)
                guard returned.map(\.path) == root.map(\.path) else { continue }
                Log("Navigation verified", detail: "Container → child folder → parent; listing matched", kind: .success)
                checked = true
                break
            } catch { continue }
        }
        Log(checked ? "Verification passed" : "Verification failed", detail: "Device folder navigation", kind: checked ? .success : .error)
        let report = activity.Export(activity.events)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? report.write(to: documents.appendingPathComponent("Verification.log"), atomically: true, encoding: .utf8)
        }
    }
}
