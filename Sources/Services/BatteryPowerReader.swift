import Foundation
import IOKit.ps

/// 内置电池状态（无电池或读失败时 percent 为 nil）。
struct BatteryPowerState: Equatable {
    var percent: Int?
    /// IOKit「Is Charging」：正在向电池补能（闪电图标）。
    var isCharging: Bool
    /// IOKit「ExternalConnected」：适配器已接；若已不再充电则显示满格/格数而非闪电。
    var isExternalPowered: Bool
    /// 系统低电量模式（macOS 12+）。
    var isLowPowerMode: Bool

    static let unavailable = BatteryPowerState(
        percent: nil,
        isCharging: false,
        isExternalPowered: false,
        isLowPowerMode: false
    )
}

/// 读取内置电池电量与供电状态（无电池设备返回 `unavailable` 式结果）。
enum BatteryPowerReader {

    /// 只采用**内置电池**字典，避免列表里先出现 UPS/AC 等条目导致充电状态读错。
    private static func powerSourceDictionary(blob: CFTypeRef, list: [CFTypeRef]) -> [String: Any]? {
        var legacyBattery: [String: Any]?
        var fallback: [String: Any]?

        for ref in list {
            guard let dict = IOPSGetPowerSourceDescription(blob, ref)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            if let present = dict[kIOPSIsPresentKey as String] as? Bool, !present { continue }

            let type = dict[kIOPSTypeKey as String] as? String ?? ""
            if type == "InternalBattery" {
                return dict
            }
            if type == "Battery", legacyBattery == nil {
                legacyBattery = dict
            }
            if fallback == nil {
                fallback = dict
            }
        }
        return legacyBattery ?? fallback
    }

    static func readState() -> BatteryPowerState {
        let lowPower: Bool = {
            if #available(macOS 12.0, *) {
                return ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            return false
        }()

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryPowerState(
                percent: nil,
                isCharging: false,
                isExternalPowered: false,
                isLowPowerMode: lowPower
            )
        }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryPowerState(
                percent: nil,
                isCharging: false,
                isExternalPowered: false,
                isLowPowerMode: lowPower
            )
        }

        guard let dict = powerSourceDictionary(blob: blob, list: list) else {
            return BatteryPowerState(
                percent: nil,
                isCharging: false,
                isExternalPowered: false,
                isLowPowerMode: lowPower
            )
        }

        let charging = Self.coercedBool(dict[kIOPSIsChargingKey as String])
        var external = Self.coercedBool(dict["ExternalConnected"])
        let powerState = dict[kIOPSPowerSourceStateKey as String] as? String
        if !external, powerState == (kIOPSACPowerValue as String) {
            external = true
        }

        var pct: Int?
        if let current = dict[kIOPSCurrentCapacityKey as String] as? Int,
           let maxCap = dict[kIOPSMaxCapacityKey as String] as? Int,
           maxCap > 0 {
            pct = min(100, max(0, current * 100 / maxCap))
        }

        return BatteryPowerState(
            percent: pct,
            isCharging: charging,
            isExternalPowered: external,
            isLowPowerMode: lowPower
        )
    }

    /// IOKit 字典里布尔有时是 `NSNumber`/`Int`，避免一直判成未充电 / 未接电。
    private static func coercedBool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let n as NSNumber: return n.boolValue
        default: return false
        }
    }
}