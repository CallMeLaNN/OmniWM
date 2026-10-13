// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM

import Foundation
import Synchronization

final class ShellIslandConfigWriter: Sendable {
    struct Write: Sendable {
        let id: ShellServiceID
        let profile: String
        let root: String
        let change: ShellIslandLayout.Change
    }

    struct Commit: Sendable {
        let id: ShellServiceID
        let revision: UInt64
        let error: String?
    }

    private struct State {
        var submitted: UInt64 = 0
        var completed: UInt64 = 0
        var deferredReload = false
    }

    let shellDirectory: URL
    private let queue = DispatchSerialQueue(label: "com.barut.OmniWM.shell.configuration", qos: .utility)
    private let state = Mutex(State())
    private let readFile: @Sendable (URL) throws -> Data
    private let writeFile: @Sendable (Data, URL) throws -> Void
    private let reloadReady: @Sendable () -> Void

    init(
        shellDirectory: URL,
        readFile: @escaping @Sendable (URL) throws -> Data = { try SettingsFileAccess.readContents(at: $0).data },
        writeFile: @escaping @Sendable (Data, URL) throws
            -> Void = { try SettingsFileAccess.writeAtomically($0, at: $1) },
        reloadReady: @escaping @Sendable () -> Void
    ) {
        self.shellDirectory = shellDirectory
        self.readFile = readFile
        self.writeFile = writeFile
        self.reloadReady = reloadReady
    }

    func deferReloadIfWriting() -> Bool {
        state.withLock { state in
            guard state.completed != state.submitted else { return false }
            state.deferredReload = true
            return true
        }
    }

    func submit(_ write: Write, completion: @escaping @Sendable (Commit) -> Void) {
        state.withLock { state in
            state.submitted += 1
            let revision = state.submitted
            queue.async { [self] in
                let failure: String?
                do {
                    let url = shellDirectory.appendingPathComponent("shell.toml")
                    let original: String
                    do {
                        original = String(decoding: try readFile(url), as: UTF8.self)
                    } catch let error as CocoaError
                        where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
                    {
                        original = ""
                    }
                    let updated = try ShellIslandLayout.persisted(
                        write.change,
                        profile: write.profile,
                        root: write.root,
                        in: original
                    )
                    if updated != original {
                        try SettingsFileAccess.ensureDirectoryExists(at: shellDirectory)
                        try writeFile(Data(updated.utf8), url)
                    }
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                }
                completion(Commit(id: write.id, revision: revision, error: failure))
                let reload = self.state.withLock { state in
                    state.completed = revision
                    guard state.completed == state.submitted, state.deferredReload else { return false }
                    state.deferredReload = false
                    return true
                }
                if reload { reloadReady() }
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
