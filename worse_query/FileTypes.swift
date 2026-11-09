// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation

struct BrowserItem: Identifiable, Hashable, Codable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    var modifiedDate: Date? = nil
    var itemCount: Int? = nil
    var resolvedPath: String? = nil
    var directoryPath: String { resolvedPath ?? path }
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
