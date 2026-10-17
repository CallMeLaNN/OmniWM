// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

import SwiftUI

struct HotkeySettingsPage<Content: View>: View {
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                SettingsCaption(subtitle)
                    .padding(.bottom, 16)
                ForEach(sections: content()) { section in
                    ForEach(section.header) { header in
                        header
                            .font(.headline)
                            .padding(.bottom, 8)
                    }
                    ForEach(section.content) { row in
                        let first = row.id == section.content.first?.id
                        let last = row.id == section.content.last?.id
                        row
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: first ? 10 : 0,
                                    bottomLeadingRadius: last ? 10 : 0,
                                    bottomTrailingRadius: last ? 10 : 0,
                                    topTrailingRadius: first ? 10 : 0
                                )
                                .fill(Color(nsColor: .controlBackgroundColor))
                            }
                            .overlay(alignment: .bottom) {
                                if !last { Divider().padding(.horizontal, 12) }
                            }
                            .padding(.bottom, last ? 20 : 0)
                    }
                }
            }
            .labeledContentStyle(AlignedSettingsLabelStyle())
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AlignedSettingsLabelStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
            Spacer(minLength: 16)
            configuration.content
        }
    }
}
