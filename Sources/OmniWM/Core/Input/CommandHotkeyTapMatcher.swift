// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import AppKit
import Carbon

struct ModifierFlagMask {
    let carbon: UInt32
    let independent: UInt64
    let left: UInt64
    let right: UInt64

    static let all: [ModifierFlagMask] = [
        ModifierFlagMask(
            carbon: UInt32(controlKey),
            independent: CGEventFlags.maskControl.rawValue,
            left: UInt64(NX_DEVICELCTLKEYMASK),
            right: UInt64(NX_DEVICERCTLKEYMASK)
        ),
        ModifierFlagMask(
            carbon: UInt32(optionKey),
            independent: CGEventFlags.maskAlternate.rawValue,
            left: UInt64(NX_DEVICELALTKEYMASK),
            right: UInt64(NX_DEVICERALTKEYMASK)
        ),
        ModifierFlagMask(
            carbon: UInt32(shiftKey),
            independent: CGEventFlags.maskShift.rawValue,
            left: UInt64(NX_DEVICELSHIFTKEYMASK),
            right: UInt64(NX_DEVICERSHIFTKEYMASK)
        ),
        ModifierFlagMask(
            carbon: UInt32(cmdKey),
            independent: CGEventFlags.maskCommand.rawValue,
            left: UInt64(NX_DEVICELCMDKEYMASK),
            right: UInt64(NX_DEVICERCMDKEYMASK)
        )
    ]
}

enum CommandHotkeyTapMatcher {
    struct Entry: Equatable {
        let binding: KeyBinding
        let command: HotkeyCommand
    }

    static func match(keyCode: UInt32, rawFlags: UInt64, entries: [Entry]) -> HotkeyCommand? {
        entries.first { matches($0.binding, keyCode: keyCode, rawFlags: rawFlags) }?.command
    }

    static func nearMiss(keyCode: UInt32, rawFlags: UInt64, entries: [Entry]) -> (entry: Entry, reason: String)? {
        for entry in entries where entry.binding.keyCode == keyCode {
            if let reason = rejectionReason(entry.binding, keyCode: keyCode, rawFlags: rawFlags) {
                return (entry, reason)
            }
        }
        return nil
    }

    private enum Rejection: Equatable {
        case keyCode
        case missing(UInt32)
        case extra(UInt32)
        case left(UInt32)
        case right(UInt32)
    }

    static func matches(_ binding: KeyBinding, keyCode: UInt32, rawFlags: UInt64) -> Bool {
        rejection(binding, keyCode: keyCode, rawFlags: rawFlags) == nil
    }

    static func rejectionReason(_ binding: KeyBinding, keyCode: UInt32, rawFlags: UInt64) -> String? {
        switch rejection(binding, keyCode: keyCode, rawFlags: rawFlags) {
        case .keyCode: return "keyCode"
        case let .missing(mask): return "needs \(KeySymbolMapper.modifierSymbols(mask))"
        case let .extra(mask): return "extra \(KeySymbolMapper.modifierSymbols(mask))"
        case let .left(mask): return "needs L\(KeySymbolMapper.modifierSymbols(mask))"
        case let .right(mask): return "needs R\(KeySymbolMapper.modifierSymbols(mask))"
        case nil: return nil
        }
    }

    private static func rejection(_ binding: KeyBinding, keyCode: UInt32, rawFlags: UInt64) -> Rejection? {
        guard binding.keyCode == keyCode else { return .keyCode }
        for mask in ModifierFlagMask.all {
            let required = binding.modifiers & mask.carbon != 0
            let down = rawFlags & mask.independent != 0
            guard required == down else { return required ? .missing(mask.carbon) : .extra(mask.carbon) }
            guard required else { continue }
            switch binding.sidedModifiers.side(for: mask.carbon) {
            case .either:
                continue
            case .left:
                guard rawFlags & mask.left != 0, rawFlags & mask.right == 0 else { return .left(mask.carbon) }
            case .right:
                guard rawFlags & mask.right != 0, rawFlags & mask.left == 0 else { return .right(mask.carbon) }
            }
        }
        return nil
    }
}
