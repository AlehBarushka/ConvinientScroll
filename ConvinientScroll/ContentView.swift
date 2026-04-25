//
//  ContentView.swift
//  ConvinientScroll
//
//  Created by aleh on 23.04.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var devicePresence: DevicePresenceMonitor
    @EnvironmentObject private var naturalScroll: NaturalScrollSettingMonitor
    @State private var isHovering = false

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.10 : 0.06))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(isHovering ? 0.28 : 0.18), lineWidth: 1)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Natural Scroll")
                        .font(.title3.weight(.semibold))
                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { naturalScroll.isNaturalScrollEnabled },
                        set: { naturalScroll.setEnabled($0, source: .user) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!naturalScroll.canWriteSystemPreference)
                }

                if let reason = naturalScroll.writeBlockedReason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 10) {
                    StatusRow(
                        title: "Mouse",
                        value: devicePresence.hasMouse ? "connected" : "not found",
                        isConnected: devicePresence.hasMouse
                    )
                    StatusRow(
                        title: "Trackpad",
                        value: devicePresence.hasTrackpad ? "connected" : "not found",
                        isConnected: devicePresence.hasTrackpad
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 320, height: 170)
        .onHover { isHovering = $0 }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let isConnected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
                .padding(.trailing, 6)

            Text(title)
                .font(.headline)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DevicePresenceMonitor())
        .environmentObject(NaturalScrollSettingMonitor())
}
