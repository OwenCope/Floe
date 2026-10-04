//
//  CalculatorTests.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

@testable import Floe
import Foundation
import Testing

struct CalculatorTests {
    private func number(_ query: String) throws -> Double {
        let result = try #require(Calculator.evaluate(query))
        let first = try #require(result.copyText.split(separator: " ").first)
        return try #require(Double(first))
    }

    @Test(arguments: [("18% of 240", 43.2), ("(2+3)*4", 20), ("2^10", 1024), ("(1+2", 3), ("10 / 4", 2.5)])
    func evaluatesArithmetic(query: String, expected: Double) throws {
        #expect(try abs(number(query) - expected) < 0.0001)
    }

    @Test func convertsUnits() throws {
        #expect(try abs(number("5 km in mi") - 3.10686) < 0.01)
        #expect(try abs(number("100 f to c") - 37.78) < 0.01)
    }

    @Test(arguments: ["42", "hello world", "1/0", "safari", ""])
    func leavesNonCalculationsAlone(query: String) {
        #expect(Calculator.evaluate(query) == nil)
    }
}
