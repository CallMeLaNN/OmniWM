// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import Foundation

struct IPCByteBuffer: ~Copyable {
    private var bytes: UnsafeMutablePointer<UInt8>
    private var count = 0
    private var capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        bytes = .allocate(capacity: capacity)
    }

    deinit {
        bytes.deallocate()
    }

    mutating func append(_ byte: UInt8) {
        if count == capacity { grow(to: count + 1) }
        (bytes + count).initialize(to: byte)
        count += 1
    }

    mutating func append(_ source: UnsafeBufferPointer<UInt8>) {
        guard let base = source.baseAddress else { return }
        if count + source.count > capacity { grow(to: count + source.count) }
        (bytes + count).initialize(from: base, count: source.count)
        count += source.count
    }

    mutating func append(_ text: String.UTF8View) {
        if text.withContiguousStorageIfAvailable({ append($0) }) == nil {
            for byte in text { append(byte) }
        }
    }

    func makeData() -> Data {
        Data(bytes: bytes, count: count)
    }

    private mutating func grow(to minimum: Int) {
        let grown = max(minimum, capacity + capacity / 2)
        let moved = UnsafeMutablePointer<UInt8>.allocate(capacity: grown)
        moved.initialize(from: bytes, count: count)
        bytes.deallocate()
        bytes = moved
        capacity = grown
    }
}
