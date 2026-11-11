// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Files Lab contributors

import Foundation
import Combine

struct OperationSnapshot: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let update: FileProgressUpdate?
}

struct OperationFeedback: Identifiable {
    let id: UUID
    let title: String
    let path: String
}

@MainActor
final class OperationStatus: ObservableObject {
    @Published private(set) var active: OperationSnapshot?
    @Published private(set) var feedback: OperationFeedback?

    func Begin(_ title: String, symbol: String = "doc.on.doc") -> UUID {
        let id = UUID()
        feedback = nil
        active = .init(id: id, title: title, symbol: symbol, update: nil)
        return id
    }

    func Update(_ id: UUID, _ update: FileProgressUpdate) {
        guard let current = active, current.id == id else { return }
        active = .init(id: id, title: current.title, symbol: current.symbol, update: update)
    }

    func Complete(_ id: UUID, title: String, path: String) {
        guard active?.id == id else { return }
        active = nil
        feedback = .init(id: id, title: title, path: path)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if feedback?.id == id { feedback = nil }
        }
    }

    func Dismiss(_ id: UUID) {
        if active?.id == id { active = nil }
    }
}
