//
//  AutoFillOptOut.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import AppKit
import ObjectiveC

/// Keeps the system's password and one-time-code AutoFill away from Floe's text fields.
enum AutoFillOptOut {
    /// AppKit offers no switch, so the controller's entry points are made to do nothing. A missing class or method is skipped.
    static func install() {
        guard let controller = NSClassFromString("NSAutoFillHeuristicController") else { return }
        let nothing: @convention(block) (AnyObject) -> Void = { _ in }
        let nothingWithArgument: @convention(block) (AnyObject, AnyObject?) -> Void = { _, _ in }
        let entryPoints: [(String, Any)] = [
            ("_showOrHideAutoFillForCurrentTextInputContextIfAppropriate", nothing),
            ("showOrHideAutoFillForCurrentTextInputContextIfAppropriate", nothing),
            ("_debounceTextInputContextUpdate", nothing),
            ("_windowDidBecomeKey:", nothingWithArgument),
            ("viewDidBecomeFirstResponder:", nothingWithArgument),
        ]
        for (name, block) in entryPoints {
            if let method = class_getInstanceMethod(controller, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(block))
            }
        }
    }
}
