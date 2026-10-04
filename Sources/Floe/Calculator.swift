//
//  Calculator.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

import Foundation

struct CalculatorResult: Equatable {
    let expression: String
    let value: String
    let copyText: String
    let detail: String?
}

enum Calculator {
    static func evaluate(_ query: String) -> CalculatorResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        if let conversion = evaluateConversion(trimmed) { return conversion }
        if let percentOf = evaluatePercentOf(trimmed) { return percentOf }
        if let plusMinus = evaluatePlusMinusPercent(trimmed) { return plusMinus }
        guard looksLikeCalculation(trimmed) else { return nil }
        guard let value = parseExpression(trimmed) else { return nil }
        guard value.isFinite else { return nil }
        let expression = collapseWhitespace(trimmed)
        return CalculatorResult(
            expression: expression,
            value: formatGrouped(value),
            copyText: formatPlain(value),
            detail: nil
        )
    }

    // MARK: - Detection

    private static func looksLikeCalculation(_ query: String) -> Bool {
        let lower = query.lowercased()
        if lower.contains("%") || lower.contains("×") || lower.contains("÷") { return true }
        if query.contains("+") || query.contains("*") || query.contains("/") || query.contains("^")
            || query.contains("(") || query.contains(")") { return true }
        if query.contains("-") { return true }
        let words = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let keywords: Set<String> = ["sqrt", "sin", "cos", "tan", "log", "ln", "abs", "round", "floor", "ceil", "pi", "e", "of"]
        return words.contains(where: { keywords.contains($0) })
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Formatting

    private static func makeFormatter(grouped: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouped
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter
    }

    private static func formatGrouped(_ value: Double) -> String {
        makeFormatter(grouped: true).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatPlain(_ value: Double) -> String {
        makeFormatter(grouped: false).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    // MARK: - Percent forms

    private static func evaluatePercentOf(_ query: String) -> CalculatorResult? {
        guard let ofRange = query.range(of: "of", options: [.caseInsensitive]) else { return nil }
        let left = String(query[..<ofRange.lowerBound])
        let right = String(query[ofRange.upperBound...])
        guard left.contains("%") else { return nil }
        let pctText = left.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let pct = parseExpression(pctText),
              let base = parseExpression(right.trimmingCharacters(in: .whitespaces)),
              pct.isFinite, base.isFinite else { return nil }
        let result = pct / 100 * base
        guard result.isFinite else { return nil }
        let expression = "\(collapseWhitespace(pctText))% of \(collapseWhitespace(right))"
        return CalculatorResult(expression: expression, value: formatGrouped(result), copyText: formatPlain(result), detail: nil)
    }

    private static func evaluatePlusMinusPercent(_ query: String) -> CalculatorResult? {
        guard query.hasSuffix("%") else { return nil }
        let withoutPct = String(query.dropLast())
        guard let opIndex = withoutPct.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        // The operator must not be a leading sign.
        let prefix = String(withoutPct[..<opIndex]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty else { return nil }
        let op = withoutPct[opIndex]
        let pctText = String(withoutPct[withoutPct.index(after: opIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !pctText.isEmpty, let pct = Double(pctText.replacingOccurrences(of: ",", with: "")), pct.isFinite else { return nil }
        guard let base = parseExpression(prefix), base.isFinite else { return nil }
        let result = op == "+" ? base + base * pct / 100 : base - base * pct / 100
        guard result.isFinite else { return nil }
        let expression = "\(collapseWhitespace(prefix)) \(op) \(collapseWhitespace(pctText))%"
        return CalculatorResult(expression: expression, value: formatGrouped(result), copyText: formatPlain(result), detail: nil)
    }

    // MARK: - Unit conversion

    private static func evaluateConversion(_ query: String) -> CalculatorResult? {
        let parts = collapseWhitespace(query).components(separatedBy: " ")
        guard parts.count == 4 else { return nil }
        let separator = parts[2].lowercased()
        guard separator == "in" || separator == "to" || separator == "as" else { return nil }
        let numberText = parts[0].replacingOccurrences(of: ",", with: "")
        guard let number = Double(numberText), number.isFinite else { return nil }
        let fromKey = parts[1].lowercased()
        let toKey = parts[3].lowercased()
        guard let converted = convert(number, from: fromKey, to: toKey) else { return nil }
        guard converted.value.isFinite else { return nil }
        return CalculatorResult(
            expression: "\(numberText) \(fromKey) → \(toKey)",
            value: "\(formatGrouped(converted.value)) \(converted.symbol)",
            copyText: "\(formatPlain(converted.value)) \(converted.symbol)",
            detail: "\(converted.fromName) to \(converted.toName)"
        )
    }

    private struct Converted {
        let value: Double
        let symbol: String
        let fromName: String
        let toName: String
    }

    private static func convert(_ number: Double, from: String, to: String) -> Converted? {
        if let fromUnit = lengthUnit(from), let toUnit = lengthUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = massUnit(from), let toUnit = massUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = temperatureUnit(from), let toUnit = temperatureUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = volumeUnit(from), let toUnit = volumeUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = dataUnit(from), let toUnit = dataUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = durationUnit(from), let toUnit = durationUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        if let fromUnit = speedUnit(from), let toUnit = speedUnit(to) {
            let result = Measurement(value: number, unit: fromUnit.unit).converted(to: toUnit.unit)
            return Converted(value: result.value, symbol: toUnit.unit.symbol, fromName: fromUnit.name, toName: toUnit.name)
        }
        return nil
    }

    private static func singular(_ s: String) -> String {
        var key = s.replacingOccurrences(of: "°", with: "")
        if key.hasSuffix("s") && key.count > 2 { key = String(key.dropLast()) }
        return key
    }

    private static func lengthUnit(_ s: String) -> (unit: UnitLength, name: String)? {
        switch singular(s) {
        case "mm", "millimeter", "millimetre": return (.millimeters, "Millimeters")
        case "cm", "centimeter", "centimetre": return (.centimeters, "Centimeters")
        case "m", "meter", "metre": return (.meters, "Meters")
        case "km", "kilometer", "kilometre": return (.kilometers, "Kilometers")
        case "in", "inch", "inche": return (.inches, "Inches")
        case "ft", "foot", "feet": return (.feet, "Feet")
        case "yd", "yard": return (.yards, "Yards")
        case "mi", "mile": return (.miles, "Miles")
        default: return nil
        }
    }

    private static func massUnit(_ s: String) -> (unit: UnitMass, name: String)? {
        switch singular(s) {
        case "g", "gram": return (.grams, "Grams")
        case "kg", "kilogram": return (.kilograms, "Kilograms")
        case "oz", "ounce": return (.ounces, "Ounces")
        case "lb", "lbs", "pound": return (.pounds, "Pounds")
        default: return nil
        }
    }

    private static func temperatureUnit(_ s: String) -> (unit: UnitTemperature, name: String)? {
        switch singular(s) {
        case "c", "celsius", "centigrade": return (.celsius, "Celsius")
        case "f", "fahrenheit": return (.fahrenheit, "Fahrenheit")
        case "k", "kelvin": return (.kelvin, "Kelvin")
        default: return nil
        }
    }

    private static func volumeUnit(_ s: String) -> (unit: UnitVolume, name: String)? {
        switch singular(s) {
        case "ml", "milliliter", "millilitre": return (.milliliters, "Milliliters")
        case "l", "liter", "litre": return (.liters, "Liters")
        case "cup": return (.cups, "Cups")
        case "floz", "fluidounce", "fluid ounce", "oz": return (.fluidOunces, "Fluid Ounces")
        case "gal", "gallon": return (.gallons, "Gallons")
        default: return nil
        }
    }

    private static func dataUnit(_ s: String) -> (unit: UnitInformationStorage, name: String)? {
        switch singular(s) {
        case "b", "byte": return (.bytes, "Bytes")
        case "kb", "kilobyte": return (.kilobytes, "Kilobytes")
        case "mb", "megabyte": return (.megabytes, "Megabytes")
        case "gb", "gigabyte": return (.gigabytes, "Gigabytes")
        case "tb", "terabyte": return (.terabytes, "Terabytes")
        default: return nil
        }
    }

    private static func durationUnit(_ s: String) -> (unit: UnitDuration, name: String)? {
        switch singular(s) {
        case "s", "sec", "second": return (.seconds, "Seconds")
        case "min", "minute": return (.minutes, "Minutes")
        case "h", "hr", "hour": return (.hours, "Hours")
        case "day": return (UnitDuration(symbol: "day", converter: UnitConverterLinear(coefficient: 86400)), "Days")
        default: return nil
        }
    }

    private static func speedUnit(_ s: String) -> (unit: UnitSpeed, name: String)? {
        switch s {
        case "kmh", "kph", "km/h": return (.kilometersPerHour, "Kilometers Per Hour")
        case "mph": return (.milesPerHour, "Miles Per Hour")
        case "m/s", "ms": return (.metersPerSecond, "Meters Per Second")
        default: return nil
        }
    }

    // MARK: - Expression parser

    private static func parseExpression(_ query: String) -> Double? {
        var text = query
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
        let open = text.filter { $0 == "(" }.count
        let close = text.filter { $0 == ")" }.count
        if open > close { text += String(repeating: ")", count: open - close) }
        var parser = ExpressionParser(text: text.lowercased())
        guard let value = parser.parse(), parser.atEnd else { return nil }
        return value
    }
}

private struct ExpressionParser {
    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case lparen
        case rparen
        case percent
        case name(String)
    }

    private var tokens: [Token] = []
    private var index = 0
    var atEnd: Bool { index >= tokens.count }

    init(text: String) {
        var chars = Array(text)
        var i = 0
        var out: [Token] = []
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" { i += 1; continue }
            if c.isNumber || c == "." {
                var j = i
                var hasDigit = false
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                    if chars[j].isNumber { hasDigit = true }
                    j += 1
                }
                if hasDigit, let value = Double(String(chars[i..<j])) {
                    out.append(.number(value))
                    i = j
                    continue
                }
                return
            }
            if c.isLetter {
                var j = i
                while j < chars.count && chars[j].isLetter { j += 1 }
                out.append(.name(String(chars[i..<j])))
                i = j
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^": out.append(.op(c))
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            case "%": out.append(.percent)
            default: return
            }
            i += 1
        }
        self.tokens = out
    }

    mutating func parse() -> Double? {
        guard !tokens.isEmpty else { return nil }
        return parseAdd()
    }

    private mutating func peek() -> Token? {
        guard index < tokens.count else { return nil }
        return tokens[index]
    }

    private mutating func parseAdd() -> Double? {
        guard var lhs = parseMul() else { return nil }
        while let token = peek(), case .op(let c) = token, (c == "+" || c == "-") {
            index += 1
            guard let rhs = parseMul(), rhs.isFinite else { return nil }
            lhs = c == "+" ? lhs + rhs : lhs - rhs
            guard lhs.isFinite else { return nil }
        }
        return lhs
    }

    private mutating func parseMul() -> Double? {
        guard var lhs = parsePow() else { return nil }
        while let token = peek() {
            if case .op(let c) = token, (c == "*" || c == "/") {
                index += 1
                guard let rhs = parsePow(), rhs.isFinite else { return nil }
                if c == "/" {
                    guard rhs != 0 else { return nil }
                    lhs = lhs / rhs
                } else {
                    lhs = lhs * rhs
                }
                guard lhs.isFinite else { return nil }
            } else if isFactorStart(token) {
                // Implicit multiplication: 2(3+4), 2 pi
                guard let rhs = parsePow(), rhs.isFinite else { return nil }
                lhs = lhs * rhs
                guard lhs.isFinite else { return nil }
            } else {
                break
            }
        }
        return lhs
    }

    private func isFactorStart(_ token: Token) -> Bool {
        switch token {
        case .number, .lparen, .name: return true
        default: return false
        }
    }

    private mutating func parsePow() -> Double? {
        guard let base = parseUnary() else { return nil }
        if let token = peek(), case .op("^") = token {
            index += 1
            guard let exp = parsePow(), exp.isFinite else { return nil }
            let result = pow(base, exp)
            guard result.isFinite else { return nil }
            return result
        }
        return base
    }

    private mutating func parseUnary() -> Double? {
        if let token = peek(), case .op(let c) = token, (c == "-" || c == "+") {
            index += 1
            guard let value = parseUnary(), value.isFinite else { return nil }
            return c == "-" ? -value : value
        }
        if let token = peek(), case .name(let name) = token {
            if name == "pi" { index += 1; return applyPostfix(Double.pi) }
            if name == "e" { index += 1; return applyPostfix(M_E) }
            if isFunction(name) {
                index += 1
                guard var arg = parseUnary(), arg.isFinite else { return nil }
                guard let result = applyFunction(name, arg), result.isFinite else { return nil }
                return applyPostfix(result)
            }
            return nil
        }
        guard var value = parsePrimary() else { return nil }
        value = applyPostfix(value) ?? Double.nan
        guard value.isFinite else { return nil }
        return value
    }

    private mutating func applyPostfix(_ value: Double) -> Double? {
        var result = value
        while let token = peek(), token == .percent {
            index += 1
            result = result / 100
        }
        return result
    }

    private mutating func parsePrimary() -> Double? {
        guard let token = peek() else { return nil }
        switch token {
        case .number(let v):
            index += 1
            return v
        case .lparen:
            index += 1
            guard let value = parseAdd() else { return nil }
            if peek() == .rparen { index += 1 }
            return value
        default:
            return nil
        }
    }

    private func isFunction(_ name: String) -> Bool {
        ["sqrt", "sin", "cos", "tan", "log", "ln", "abs", "round", "floor", "ceil"].contains(name)
    }

    private func applyFunction(_ name: String, _ arg: Double) -> Double? {
        switch name {
        case "sqrt": return arg >= 0 ? sqrt(arg) : nil
        case "sin": return sin(arg)
        case "cos": return cos(arg)
        case "tan": return tan(arg)
        case "log": return arg > 0 ? log10(arg) : nil
        case "ln": return arg > 0 ? log(arg) : nil
        case "abs": return abs(arg)
        case "round": return arg.rounded()
        case "floor": return floor(arg)
        case "ceil": return ceil(arg)
        default: return nil
        }
    }
}
