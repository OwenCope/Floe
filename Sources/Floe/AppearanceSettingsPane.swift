//
//  AppearanceSettingsPane.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Thaw's menu-bar appearance controls, applied to the launcher panel: a tint
/// over the glass, an optional border, and a drop shadow that follows the
/// launcher's rounded shape.
struct AppearanceSettingsPane: View {
    @ObservedObject var settings: AppSettings

    private var solidColor: Binding<Color> {
        Binding(
            get: { settings.launcherTint.solid.color },
            set: { settings.launcherTint.solid = StoredColor($0) }
        )
    }

    private var gradientTop: Binding<Color> {
        Binding(
            get: { settings.launcherTint.gradient.top.color },
            set: { settings.launcherTint.gradient.top = StoredColor($0) }
        )
    }

    private var gradientBottom: Binding<Color> {
        Binding(
            get: { settings.launcherTint.gradient.bottom.color },
            set: { settings.launcherTint.gradient.bottom = StoredColor($0) }
        )
    }

    private var borderColor: Binding<Color> {
        Binding(
            get: { settings.launcherBorder.color.color },
            set: { settings.launcherBorder.color = StoredColor($0) }
        )
    }

    var body: some View {
        Form {
            ThawSection("Tint") {
                Picker("Style", selection: $settings.launcherTint.kind) {
                    ForEach(LauncherTintKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                switch settings.launcherTint.kind {
                case .none:
                    EmptyView()
                case .solid:
                    ColorPicker("Colour", selection: solidColor, supportsOpacity: false)
                case .gradient:
                    ColorPicker("Top colour", selection: gradientTop, supportsOpacity: false)
                    ColorPicker("Bottom colour", selection: gradientBottom, supportsOpacity: false)
                    Slider(value: $settings.launcherTint.gradient.angle, in: 0 ... 360) {
                        Text("Angle")
                    } minimumValueLabel: {
                        Text("0°")
                    } maximumValueLabel: {
                        Text("360°")
                    }
                }
                if settings.launcherTint.kind != .none {
                    Slider(value: $settings.launcherTint.opacity, in: 0.05 ... 1) {
                        Text("Opacity")
                    } minimumValueLabel: {
                        Text("5%")
                    } maximumValueLabel: {
                        Text("100%")
                    }
                }
            }
            ThawSection("Border") {
                Toggle("Draw a border", isOn: $settings.launcherShowsBorder)
                if settings.launcherShowsBorder {
                    ColorPicker("Colour", selection: borderColor, supportsOpacity: false)
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
}
