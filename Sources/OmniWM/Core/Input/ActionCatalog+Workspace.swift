// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Carbon
import OmniWMIPC

enum WorkspaceNumberActionKind: String, CaseIterable {
    case switchWorkspace
    case moveToWorkspace
    case moveColumnToWorkspace

    var rowGroup: WorkspaceNumberActionKind {
        self == .moveToWorkspace ? .switchWorkspace : self
    }

    static func parse(_ id: String) -> (kind: WorkspaceNumberActionKind, index: Int)? {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let kind = WorkspaceNumberActionKind(rawValue: parts[0]),
              let index = Int(parts[1]),
              String(index) == parts[1]
        else { return nil }
        return (kind, index)
    }
}

extension ActionCatalog {
    static func appendWorkspaceNumberBindings(_ specs: inout [ActionSpec]) {
        for (idx, code) in digitCodes.enumerated() {
            specs.append(
                action(
                    id: "switchWorkspace.\(idx)",
                    command: .workspace(.switchTo(idx)),
                    category: .workspace,
                    binding: KeyBinding(keyCode: code, modifiers: UInt32(optionKey))
                )
            )
            specs.append(
                action(
                    id: "moveToWorkspace.\(idx)",
                    command: .workspace(.moveTo(idx)),
                    category: .workspace,
                    binding: KeyBinding(keyCode: code, modifiers: UInt32(optionKey | shiftKey))
                )
            )
        }
    }

    static func workspaceNumberSpecs(forWorkspaceNumber number: Int) -> [ActionSpec] {
        WorkspaceNumberActionKind.allCases.compactMap { workspaceNumberSpec(kind: $0, index: number - 1) }
    }

    static func workspaceNumberSpec(for id: String) -> ActionSpec? {
        WorkspaceNumberActionKind.parse(id).flatMap { workspaceNumberSpec(kind: $0.kind, index: $0.index) }
    }

    static func workspaceNumberSpec(for command: HotkeyCommand) -> ActionSpec? {
        switch command {
        case let .workspace(.switchTo(index)): workspaceNumberSpec(kind: .switchWorkspace, index: index)
        case let .workspace(.moveTo(index)): workspaceNumberSpec(kind: .moveToWorkspace, index: index)
        case let .column(.moveToWorkspace(index)): workspaceNumberSpec(kind: .moveColumnToWorkspace, index: index)
        default: nil
        }
    }

    private static func workspaceNumberSpec(kind: WorkspaceNumberActionKind, index: Int) -> ActionSpec? {
        guard index >= digitCodes.count, index < Int.max else { return nil }
        let id = "\(kind.rawValue).\(index)"
        return switch kind {
        case .switchWorkspace:
            action(id: id, command: .workspace(.switchTo(index)), category: .workspace, binding: .unassigned)
        case .moveToWorkspace:
            action(id: id, command: .workspace(.moveTo(index)), category: .workspace, binding: .unassigned)
        case .moveColumnToWorkspace:
            action(
                id: id,
                command: .column(.moveToWorkspace(index)),
                category: .workspace,
                binding: .unassigned,
                visibility: .advanced
            )
        }
    }

    static func appendWorkspaceSlotBindings(_ specs: inout [ActionSpec]) {
        for slot in workspaceSlotRange {
            specs.append(contentsOf: [
                action(
                    id: "switchWorkspaceSlot.\(slot)",
                    command: .workspace(.switchSlot(slot)),
                    category: .workspace,
                    binding: .unassigned,
                    keywords: ["slot", "position", "monitor"]
                ),
                action(
                    id: "moveToWorkspaceSlot.\(slot)",
                    command: .workspace(.moveToSlot(slot)),
                    category: .workspace,
                    binding: .unassigned,
                    keywords: ["slot", "position", "monitor"]
                )
            ])
        }
    }

    static func appendWorkspaceHistoryBinding(_ specs: inout [ActionSpec]) {
        specs.append(
            action(
                id: "workspaceBackAndForth",
                command: .workspace(.backAndForth),
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | controlKey)),
                keywords: ["back and forth", "previous workspace"]
            )
        )
    }

    static func appendWorkspaceCycleBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "switchWorkspace.next",
                command: .workspace(.next),
                category: .workspace,
                binding: .unassigned
            ),
            action(
                id: "switchWorkspace.previous",
                command: .workspace(.previous),
                category: .workspace,
                binding: .unassigned
            )
        ])
    }

    static func appendWorkspaceTransferBindings(_ specs: inout [ActionSpec]) {
        specs.append(contentsOf: [
            action(
                id: "moveWindowToWorkspaceUp",
                command: .workspace(.moveUp),
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey | controlKey | shiftKey))
            ),
            action(
                id: "moveWindowToWorkspaceDown",
                command: .workspace(.moveDown),
                category: .workspace,
                binding: KeyBinding(
                    keyCode: UInt32(kVK_DownArrow),
                    modifiers: UInt32(optionKey | controlKey | shiftKey)
                )
            ),
            action(
                id: "moveColumnToWorkspaceUp",
                command: .column(.moveToWorkspaceUp),
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_PageUp), modifiers: UInt32(optionKey | controlKey | shiftKey))
            ),
            action(
                id: "moveColumnToWorkspaceDown",
                command: .column(.moveToWorkspaceDown),
                category: .workspace,
                binding: KeyBinding(keyCode: UInt32(kVK_PageDown), modifiers: UInt32(optionKey | controlKey | shiftKey))
            )
        ])
    }
}
