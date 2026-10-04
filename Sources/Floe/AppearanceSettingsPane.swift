//
//  AppearanceSettingsPane.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import SwiftUI
import ThawUI

/// Thaw's menu-bar appearance controls, applied to the launcher panel: glass, tint, border and shadow.
/// The preview draws them at miniature scale, so a change reads without summoning the panel.
struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    /// The tint the single editor writes: light when the tints are separate,
    /// which is also the tint a static configuration draws.
    private var editing: Binding<LauncherTint> {
        Binding(
            get: { settings.launcherTintLight },
            set: { settings.launcherTintLight = $0 }
        )
    }

    private var editingDark: Binding<LauncherTint> {
        Binding(
            get: { settings.launcherTintDark },
            set: { settings.launcherTintDark = $0 }
        )
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { settings.launcherBorder.color.color },
            set: { settings.launcherBorder.color = StoredColor($0) }
        )
    }

    private var glassColor: Binding<Color> {
        Binding(
            get: { settings.launcherGlass.color.color },
            set: { settings.launcherGlass.color = StoredColor($0) }
        )
    }

    /// Following the system is its own flag, so the picker has one more choice than there are styles.
    private enum GlassChoice: Hashable {
        case matchSystem
        case style(LauncherGlassStyle)
    }

    private var glassChoice: Binding<GlassChoice> {
        Binding(
            get: { settings.launcherGlass.followsSystem ? .matchSystem : .style(settings.launcherGlass.style) },
            set: { choice in
                switch choice {
                case .matchSystem:
                    settings.launcherGlass.followsSystem = true
                case let .style(style):
                    settings.launcherGlass.followsSystem = false
                    settings.launcherGlass.style = style
                }
            }
        )
    }

    private func colorBinding(_ tint: Binding<LauncherTint>, _ keyPath: WritableKeyPath<LauncherGradient, StoredColor>) -> Binding<Color> {
        Binding(
            get: { tint.wrappedValue.gradient[keyPath: keyPath].color },
            set: { tint.wrappedValue.gradient[keyPath: keyPath] = StoredColor($0) }
        )
    }

    var body: some View {
        Form {
            ThawSection("Preview") {
                LauncherAppearancePreview(
                    glass: settings.launcherGlass,
                    tint: settings.launcherTint(for: colorScheme),
                    border: settings.launcherShowsBorder ? settings.launcherBorder : nil,
                    hasShadow: settings.launcherShowsShadow
                )
                .frame(maxWidth: .infinity)
            }
            ThawSection("Layout") {
                Picker("Launcher layout", selection: $settings.launcherLayout) {
                    ForEach(LauncherLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                Text("Extended always shows the list. Compact shows only the search bar until you type.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ThawSection("Glass") {
                Picker("Effect", selection: glassChoice) {
                    Text("Match System").tag(GlassChoice.matchSystem)
                    ForEach(LauncherGlassStyle.allCases) { style in
                        Text(style.title).tag(GlassChoice.style(style))
                    }
                }
                .help("Match System follows Liquid Glass in System Settings → Appearance: Regular while it's Tinted, Clear while it's Clear.")
                // Only the Liquid styles take a wash; Regular and Clear are the system's glass as it is.
                if settings.launcherGlass.resolvedStyle().usesTint {
                    Toggle("Tint the glass", isOn: $settings.launcherGlass.isColored)
                    if settings.launcherGlass.isColored {
                        ColorPicker("Tint color", selection: glassColor, supportsOpacity: false)
                        Slider(value: $settings.launcherGlass.opacity, in: 0.05 ... 1) {
                            Text("Opacity")
                        } minimumValueLabel: {
                            Text("5%")
                        } maximumValueLabel: {
                            Text("100%")
                        }
                    }
                }
            }
            ThawSection("Tint") {
                Toggle("Separate light and dark tints", isOn: $settings.launcherTintIsDynamic)
                if settings.launcherTintIsDynamic {
                    tintControls("Light appearance", editing)
                    tintControls("Dark appearance", editingDark)
                } else {
                    tintControls("Tint", editing)
                }
            }
            ThawSection("Border") {
                Toggle("Draw a border", isOn: $settings.launcherShowsBorder)
                if settings.launcherShowsBorder {
                    ColorPicker("Color", selection: borderColor, supportsOpacity: false)
                    Slider(value: $settings.launcherBorder.width, in: 0.5 ... 4) {
                        Text("Width")
                    } minimumValueLabel: {
                        Text("0.5 pt")
                    } maximumValueLabel: {
                        Text("4 pt")
                    }
                }
            }
            ThawSection("Shadow") {
                Toggle("Drop shadow", isOn: $settings.launcherShowsShadow)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func tintControls(_ title: String, _ tint: Binding<LauncherTint>) -> some View {
        let solid = Binding(
            get: { tint.wrappedValue.solid.color },
            set: { tint.wrappedValue.solid = StoredColor($0) }
        )
        let opacity = Binding(
            get: { tint.wrappedValue.opacity },
            set: { tint.wrappedValue.opacity = $0 }
        )
        Picker(title, selection: tint.kind) {
            ForEach(LauncherTintKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        switch tint.wrappedValue.kind {
        case .none:
            EmptyView()
        case .solid:
            ColorPicker("Color", selection: solid, supportsOpacity: false)
        case .gradient:
            ColorPicker("Start color", selection: colorBinding(tint, \.start), supportsOpacity: false)
            ColorPicker("End color", selection: colorBinding(tint, \.end), supportsOpacity: false)
            Slider(value: tint.gradient.angle, in: 0 ... 360) {
                Text("Angle")
            } minimumValueLabel: {
                Text("0°")
            } maximumValueLabel: {
                Text("360°")
            }
        }
        if tint.wrappedValue.kind != .none {
            Slider(value: opacity, in: 0.05 ... 1) {
                Text("Opacity")
            } minimumValueLabel: {
                Text("5%")
            } maximumValueLabel: {
                Text("100%")
            }
        }
    }
}

/// A miniature launcher that runs the exact panel appearance pipeline, so the
/// glass, tint, border and shadow read live next to their controls.
struct LauncherAppearancePreview: View {
    let glass: LauncherGlass
    let tint: LauncherTint
    let border: LauncherBorder?
    let hasShadow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Search")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quinary, in: Capsule(style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                previewRow(width: 150)
                previewRow(width: 110)
            }
        }
        .padding(12)
        .modifier(LauncherPanelAppearance(glass: glass, tint: tint, border: border, hasShadow: hasShadow))
        .padding(6)
    }

    private func previewRow(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle().fill(.quinary).frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.quinary)
                .frame(width: width, height: 8)
            Spacer()
        }
    }
}
