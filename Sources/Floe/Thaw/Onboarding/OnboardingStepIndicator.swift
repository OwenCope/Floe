//
//  OnboardingStepIndicator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3; the spoken label is Floe's own string.

import SwiftUI
import ThawUI

/// Dots report progress rather than acting as buttons.
/// VoiceOver reads the position as one sentence, not unlabeled circles.
struct OnboardingStepIndicator: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: ThawSpacing.base) {
            ForEach(1 ... max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step) of \(total)", comment: "Spoken for the dots that show how far the welcome window has got. Both placeholders are numbers."))
    }
}
