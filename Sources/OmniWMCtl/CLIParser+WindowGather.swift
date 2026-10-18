// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation
import OmniWMIPC

extension CLIParser {
    static let windowGatherReachFlag = "--from"

    static func parseWindowGatherRequest(id: String, arguments: [String]) throws -> IPCRequest {
        var reach: IPCWindowGatherReach?
        var windowIds: [String] = []
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            guard argument.hasPrefix("--") else {
                windowIds.append(argument)
                continue
            }
            guard argument == windowGatherReachFlag, reach == nil,
                  let value = remaining.popFirst().flatMap(IPCWindowGatherReach.init(rawValue:))
            else {
                throw CLIParseError.usage(usageText)
            }
            reach = value
        }
        guard !windowIds.isEmpty else {
            throw CLIParseError.usage(usageText)
        }
        return IPCRequest(
            id: id,
            windowGather: IPCWindowGatherRequest(windowIds: windowIds, from: reach ?? .workspace)
        )
    }
}
