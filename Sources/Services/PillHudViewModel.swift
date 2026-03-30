import Foundation
import SwiftUI

@MainActor
final class PillHudViewModel: ObservableObject {

    @Published private(set) var batteryState = BatteryPowerState.unavailable
    @Published private(set) var downloadText = "—"
    @Published private(set) var uploadText = "—"

    private var timer: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastSampleTime: Date?
    private var didPrimeNetSample = false

    func start() {
        stop()
        didPrimeNetSample = false
        lastSampleTime = nil
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        batteryState = BatteryPowerReader.readState()
        refreshNetwork()
    }

    private func refreshNetwork() {
        guard let pair = NetworkThroughputReader.cumulativeBytes() else {
            downloadText = "↓ —"
            uploadText = "↑ —"
            return
        }

        let now = Date()

        if !didPrimeNetSample {
            lastBytesIn = pair.0
            lastBytesOut = pair.1
            lastSampleTime = now
            didPrimeNetSample = true
            downloadText = "↓ —"
            uploadText = "↑ —"
            return
        }

        guard let t0 = lastSampleTime else { return }

        let dt = max(now.timeIntervalSince(t0), 0.05)
        let din = Double(pair.0 &- lastBytesIn)
        let dout = Double(pair.1 &- lastBytesOut)

        lastBytesIn = pair.0
        lastBytesOut = pair.1
        lastSampleTime = now

        let downBps = max(0, din) / dt
        let upBps = max(0, dout) / dt

        downloadText = "↓ " + Self.formatRate(downBps)
        uploadText = "↑ " + Self.formatRate(upBps)
    }

    private static func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1, bytesPerSecond > 0 {
            return "<1 B/s"
        }
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
        let kb = bytesPerSecond / 1024
        if kb < 1024 {
            return kb < 10 ? String(format: "%.1f KB/s", kb) : String(format: "%.0f KB/s", kb)
        }
        let mb = kb / 1024
        if mb < 1024 {
            return mb < 10 ? String(format: "%.1f MB/s", mb) : String(format: "%.0f MB/s", mb)
        }
        return String(format: "%.1f GB/s", mb / 1024)
    }
}
