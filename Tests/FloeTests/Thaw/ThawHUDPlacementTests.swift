//
//  ThawHUDPlacementTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import CoreGraphics
@testable import Floe
import Testing

struct ThawHUDPlacementTests {
    /// A second display to the right of the main one, so the origin is not zero.
    private let screen = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

    @Test func theCapsuleSitsAtTheChosenEndOfTheScreen() {
        #expect(ThawHUDPlacement.leading.originX(screenFrame: screen, width: 200) == 1528)
        #expect(ThawHUDPlacement.center.originX(screenFrame: screen, width: 200) == 2372)
        #expect(ThawHUDPlacement.trailing.originX(screenFrame: screen, width: 200) == 3216)
    }

    @Test func everyPlacementHasItsOwnLabel() {
        let labels = ThawHUDPlacement.allCases.map(\.label)
        #expect(labels == ["Top left", "Top center", "Top right"])
    }

    @Test func aShortLabelStillGetsTheMinimumCapsule() {
        let size = ThawHUDPlacement.size(fitting: CGSize(width: 40, height: 20), screenFrame: screen)
        #expect(size == ThawHUDPlacement.minimumSize)
    }

    @Test func theCapsuleSizesToItsText() {
        let size = ThawHUDPlacement.size(fitting: CGSize(width: 310, height: 40), screenFrame: screen)
        #expect(size == CGSize(width: 310, height: 40))
    }

    @Test func textWiderThanTheScreenIsCappedInsideTheEdgeInsets() {
        let size = ThawHUDPlacement.size(fitting: CGSize(width: 4054, height: 34), screenFrame: screen)
        #expect(size.width == 1920 - 2 * ThawHUDPlacement.edgeInset)
    }

    @Test func aScreenNarrowerThanTheMinimumKeepsTheMinimumWidth() {
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 100)
        let size = ThawHUDPlacement.size(fitting: CGSize(width: 500, height: 34), screenFrame: narrow)
        #expect(size.width == ThawHUDPlacement.minimumSize.width)
    }

    @Test func theMenuBarHeightIsTheStripAboveTheVisibleFrame() {
        let visible = CGRect(x: 1512, y: 70, width: 1920, height: 973)
        #expect(ThawHUDPlacement.menuBarHeight(screenFrame: screen, visibleFrame: visible, fallback: 24) == 37)
    }

    @Test func aHiddenMenuBarFallsBackToTheGivenHeight() {
        #expect(ThawHUDPlacement.menuBarHeight(screenFrame: screen, visibleFrame: screen, fallback: 24) == 24)
    }

    @Test func theFrameSitsJustBelowTheMenuBar() {
        let frame = ThawHUDPlacement.center.frame(fitting: CGSize(width: 200, height: 36), screenFrame: screen, menuBarHeight: 37)
        #expect(frame == CGRect(x: 2372, y: 1080 - 37 - ThawHUDPlacement.gap - 36, width: 200, height: 36))
    }

    @Test func aCappedCapsuleStaysOnItsScreenAtEveryPlacement() {
        for placement in ThawHUDPlacement.allCases {
            let frame = placement.frame(fitting: CGSize(width: 9000, height: 34), screenFrame: screen, menuBarHeight: 24)
            #expect(screen.contains(frame), "\(placement)")
        }
    }
}
