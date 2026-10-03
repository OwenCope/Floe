//
//  OnboardingSequencer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Ported to Floe from Thaw 3: Floe runs without any grant, so there is no recovery stage and no
//  tour version, and the access step is skipped only when every permission is granted. The step
//  order and the step indicator's numbers moved here from the onboarding view so they are tested.

/// The one decision about what the onboarding window shows when it opens.
///
/// One pure function so its callers cannot disagree. The access step
/// rests on the live grants, never a stored flag, because a TCC grant survives
/// a defaults wipe.
enum OnboardingSequencer {
    /// What the onboarding window renders.
    enum Stage: Equatable, Sendable {
        /// The full onboarding sequence. skipsAccessStep is true when every
        /// grant is already in place.
        case onboarding(skipsAccessStep: Bool)

        /// Nothing to show; the window should not be opened.
        case none
    }

    /// Resolves the stage from the stored flag and the live grants.
    ///
    /// - Parameters:
    ///   - hasSeenOnboarding: Whether the user has finished or skipped the tour once.
    ///   - allPermissionsGranted: Whether every grant is in place
    ///     right now, never a persisted value.
    ///   - replayRequested: true when the user asked to see onboarding
    ///     again from Settings, which wins over the stored flag.
    static func stage(
        hasSeenOnboarding: Bool,
        allPermissionsGranted: Bool,
        replayRequested: Bool = false
    ) -> Stage {
        if replayRequested || !hasSeenOnboarding {
            return .onboarding(skipsAccessStep: allPermissionsGranted)
        }
        return .none
    }
}

/// The screens of the onboarding flow, in order.
enum OnboardingStep: Equatable, Sendable {
    case welcome
    case tour
    case access

    /// A position for the step indicator.
    struct Progress: Equatable, Sendable {
        let step: Int
        let total: Int
    }

    /// The step after this one, or nil when this one ends the flow.
    func next(skipsAccessStep: Bool) -> OnboardingStep? {
        switch self {
        case .welcome: .tour
        case .tour: skipsAccessStep ? nil : .access
        case .access: nil
        }
    }

    /// Hide numbering on welcome and when the tour is the only step, since "1 of 1" conveys no progress.
    func progress(skipsAccessStep: Bool) -> Progress? {
        switch self {
        case .welcome: nil
        case .tour: skipsAccessStep ? nil : Progress(step: 1, total: 2)
        case .access: Progress(step: 2, total: 2)
        }
    }
}
