//
//  OnboardingSequencerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  Floe changes © 2026 René Jiménez, under the same license.
//
//  Adapted from Thaw 3's suite to Floe's sequencer: no recovery stage and no tour version.
//  The step order cases are Floe's.

@testable import Floe
import Testing

struct OnboardingSequencerTests {
    private static nonisolated let bools = [false, true]

    @Test(arguments: bools, bools)
    func aReplayRequestAlwaysYieldsOnboarding(hasSeenOnboarding: Bool, allPermissionsGranted: Bool) {
        let stage = OnboardingSequencer.stage(
            hasSeenOnboarding: hasSeenOnboarding,
            allPermissionsGranted: allPermissionsGranted,
            replayRequested: true
        )
        #expect(stage == .onboarding(skipsAccessStep: allPermissionsGranted))
    }

    @Test(arguments: bools)
    func anUnseenTourYieldsOnboardingAndSkipsAccessOnlyWhenEverythingIsGranted(allPermissionsGranted: Bool) {
        let stage = OnboardingSequencer.stage(hasSeenOnboarding: false, allPermissionsGranted: allPermissionsGranted)
        #expect(stage == .onboarding(skipsAccessStep: allPermissionsGranted))
    }

    @Test(arguments: bools)
    func aSeenTourYieldsNothingWhateverIsGranted(allPermissionsGranted: Bool) {
        // Floe runs without any grant, so a missing one never reopens the window.
        let stage = OnboardingSequencer.stage(hasSeenOnboarding: true, allPermissionsGranted: allPermissionsGranted)
        #expect(stage == .none)
    }
}

struct OnboardingStepTests {
    @Test func theFullFlowRunsWelcomeTourAccess() {
        #expect(OnboardingStep.welcome.next(skipsAccessStep: false) == .tour)
        #expect(OnboardingStep.tour.next(skipsAccessStep: false) == .access)
        #expect(OnboardingStep.access.next(skipsAccessStep: false) == nil)
    }

    @Test func theFlowEndsAtTheTourWhenAccessIsSkipped() {
        #expect(OnboardingStep.welcome.next(skipsAccessStep: true) == .tour)
        #expect(OnboardingStep.tour.next(skipsAccessStep: true) == nil)
    }

    @Test(arguments: [false, true])
    func theWelcomeScreenIsNotNumbered(skipsAccessStep: Bool) {
        #expect(OnboardingStep.welcome.progress(skipsAccessStep: skipsAccessStep) == nil)
    }

    @Test func theTourAndAccessAreNumberedOneAndTwoOfTwo() {
        #expect(OnboardingStep.tour.progress(skipsAccessStep: false) == OnboardingStep.Progress(step: 1, total: 2))
        #expect(OnboardingStep.access.progress(skipsAccessStep: false) == OnboardingStep.Progress(step: 2, total: 2))
    }

    @Test func aTourThatIsTheOnlyStepIsNotNumbered() {
        #expect(OnboardingStep.tour.progress(skipsAccessStep: true) == nil)
    }
}
