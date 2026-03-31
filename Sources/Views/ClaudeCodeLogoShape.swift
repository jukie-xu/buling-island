import SwiftUI

/// Claude Code logo path rendered from the provided SVG `d` data.
struct ClaudeCodeLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        ClaudeCodeLogoPathCache.shared.path(in: rect)
    }
}

private final class ClaudeCodeLogoPathCache {
    static let shared = ClaudeCodeLogoPathCache()

    private let unitPath: Path
    private let bounds: CGRect

    private init() {
        let d = "m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 2.9.2 6.3.5 9.5.6 6.9.4L38 49.1h1.6l.2-.7-.5-.4-.4-.4L29 41l-10.6-7-5.6-4.1-3-2-1.5-2-.6-4.2 2.7-3 3.7.3.9.2 3.7 2.9 8 6.1L37 36l1.5 1.2.6-.4.1-.3-.7-1.1L33 25l-6-10.4-2.7-4.3-.7-2.6c-.3-1-.4-2-.4-3l3-4.2L28 0l4.2.6L33.8 2l2.6 6 4.1 9.3L47 29.9l2 3.8 1 3.4.3 1h.7v-.5l.5-7.2 1-8.7 1-11.2.3-3.2 1.6-3.8 3-2L61 2.6l2 2.9-.3 1.8-1.1 7.7L59 27.1l-1.5 8.2h.9l1-1.1 4.1-5.4 6.9-8.6 3-3.5L77 13l2.3-1.8h4.3l3.1 4.7-1.4 4.9-4.4 5.6-3.7 4.7-5.3 7.1-3.2 5.7.3.4h.7l12-2.6 6.4-1.1 7.6-1.3 3.5 1.6.4 1.6-1.4 3.4-8.2 2-9.6 2-14.3 3.3-.2.1.2.3 6.4.6 2.8.2h6.8l12.6 1 3.3 2 1.9 2.7-.3 2-5.1 2.6-6.8-1.6-16-3.8-5.4-1.3h-.8v.4l4.6 4.5 8.3 7.5L89 80.1l.5 2.4-1.3 2-1.4-.2-9.2-7-3.6-3-8-6.8h-.5v.7l1.8 2.7 9.8 14.7.5 4.5-.7 1.4-2.6 1-2.7-.6-5.8-8-6-9-4.7-8.2-.5.4-2.9 30.2-1.3 1.5-3 1.2-2.5-2-1.4-3 1.4-6.2 1.6-8 1.3-6.4 1.2-7.9.7-2.6v-.2H49L43 72l-9 12.3-7.2 7.6-1.7.7-3-1.5.3-2.8L24 86l10-12.8 6-7.9 4-4.6-.1-.5h-.3L17.2 77.4l-4.7.6-2-2 .2-3 1-1 8-5.5Z"
        let parser = MiniSVGPathParser(pathData: d)
        self.unitPath = parser.path
        self.bounds = parser.bounds.isNull ? CGRect(x: 0, y: 0, width: 100, height: 100) : parser.bounds
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / bounds.width
        let sy = rect.height / bounds.height
        let scale = min(sx, sy)
        let tx = rect.minX + (rect.width - bounds.width * scale) / 2 - bounds.minX * scale
        let ty = rect.minY + (rect.height - bounds.height * scale) / 2 - bounds.minY * scale
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: tx, y: ty)
        t = t.scaledBy(x: scale, y: scale)
        return unitPath.applying(t)
    }
}

private struct MiniSVGPathParser {
    var pathData: String
    private(set) var path = Path()
    private(set) var bounds: CGRect = .null

    private var i = 0
    private var chars: [Character] = []
    private var cmd: Character = " "
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero

    init(pathData: String) {
        self.pathData = pathData
        var m = self
        m.chars = Array(pathData)
        m.parse()
        self = m
    }

    private mutating func parse() {
        while true {
            skipSeparators()
            guard i < chars.count else { break }
            if isCommand(chars[i]) {
                cmd = chars[i]
                i += 1
            } else if cmd == " " {
                break
            }
            parseCommand()
        }
    }

    private mutating func parseCommand() {
        switch cmd {
        case "M", "m":
            parseMove()
        case "L", "l":
            parseLine()
        case "H", "h":
            parseHorizontal()
        case "V", "v":
            parseVertical()
        case "C", "c":
            parseCubic()
        case "Z", "z":
            path.closeSubpath()
            current = subpathStart
        default:
            skipUntilNextCommand()
        }
    }

    private mutating func parseMove() {
        guard let x = readNumber(), let y = readNumber() else { return }
        let p = point(x: x, y: y, relative: cmd == "m")
        path.move(to: p)
        current = p
        subpathStart = p
        include(p)
        while let nx = readNumber(), let ny = readNumber() {
            let np = point(x: nx, y: ny, relative: cmd == "m")
            path.addLine(to: np)
            current = np
            include(np)
        }
    }

    private mutating func parseLine() {
        while let x = readNumber(), let y = readNumber() {
            let p = point(x: x, y: y, relative: cmd == "l")
            path.addLine(to: p)
            current = p
            include(p)
        }
    }

    private mutating func parseHorizontal() {
        while let x = readNumber() {
            let nx = cmd == "h" ? current.x + x : x
            let p = CGPoint(x: nx, y: current.y)
            path.addLine(to: p)
            current = p
            include(p)
        }
    }

    private mutating func parseVertical() {
        while let y = readNumber() {
            let ny = cmd == "v" ? current.y + y : y
            let p = CGPoint(x: current.x, y: ny)
            path.addLine(to: p)
            current = p
            include(p)
        }
    }

    private mutating func parseCubic() {
        while let x1 = readNumber(),
              let y1 = readNumber(),
              let x2 = readNumber(),
              let y2 = readNumber(),
              let x = readNumber(),
              let y = readNumber() {
            let p1 = point(x: x1, y: y1, relative: cmd == "c")
            let p2 = point(x: x2, y: y2, relative: cmd == "c")
            let p = point(x: x, y: y, relative: cmd == "c")
            path.addCurve(to: p, control1: p1, control2: p2)
            current = p
            include(p1)
            include(p2)
            include(p)
        }
    }

    private mutating func point(x: CGFloat, y: CGFloat, relative: Bool) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    private mutating func include(_ p: CGPoint) {
        let r = CGRect(x: p.x, y: p.y, width: 0, height: 0)
        bounds = bounds.isNull ? r : bounds.union(r)
    }

    private mutating func readNumber() -> CGFloat? {
        skipSeparators()
        guard i < chars.count else { return nil }
        if isCommand(chars[i]) { return nil }
        let start = i
        var hasDigit = false
        if chars[i] == "-" || chars[i] == "+" { i += 1 }
        while i < chars.count && chars[i].isNumber {
            hasDigit = true
            i += 1
        }
        if i < chars.count && chars[i] == "." {
            i += 1
            while i < chars.count && chars[i].isNumber {
                hasDigit = true
                i += 1
            }
        }
        guard hasDigit else { i = start; return nil }
        let s = String(chars[start..<i])
        return CGFloat(Double(s) ?? 0)
    }

    private mutating func skipSeparators() {
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" {
                i += 1
            } else {
                break
            }
        }
    }

    private func isCommand(_ c: Character) -> Bool {
        "MmLlHhVvCcZz".contains(c)
    }

    private mutating func skipUntilNextCommand() {
        while i < chars.count, !isCommand(chars[i]) {
            i += 1
        }
    }
}
