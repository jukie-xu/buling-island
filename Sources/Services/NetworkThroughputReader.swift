import Foundation

/// 通过 `netstat -ibn` 解析各 `en*` 接口的累计收发字节并求和。
enum NetworkThroughputReader {

    static func cumulativeBytes() -> (UInt64, UInt64)? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        proc.arguments = ["-ibn"]
        proc.standardOutput = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }

        guard proc.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first(where: { $0.contains("Ibytes") && $0.contains("Obytes") }),
              let iIdx = columnIndex(headerLine, token: "Ibytes"),
              let oIdx = columnIndex(headerLine, token: "Obytes")
        else {
            return nil
        }

        var sumIn: UInt64 = 0
        var sumOut: UInt64 = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("en") else { continue }
            let cols = splitColumns(trimmed)
            guard cols.count > max(iIdx, oIdx) else { continue }
            if let ib = parseUInt(cols[iIdx]) { sumIn += ib }
            if let ob = parseUInt(cols[oIdx]) { sumOut += ob }
        }

        return (sumIn, sumOut)
    }

    private static func columnIndex(_ headerLine: String, token: String) -> Int? {
        let cols = splitColumns(headerLine)
        return cols.firstIndex(of: token)
    }

    private static func splitColumns(_ line: String) -> [String] {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    private static func parseUInt(_ s: String) -> UInt64? {
        let cleaned = s.replacingOccurrences(of: ",", with: "")
        return UInt64(cleaned)
    }
}
