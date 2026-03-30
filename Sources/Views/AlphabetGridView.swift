import SwiftUI

private struct AlphabetIndexLetterYPreference: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        nextValue().forEach { value[$0.key] = $0.value }
    }
}

struct AlphabetGridView: View {

    let apps: [AppInfo]
    let onAppTap: (AppInfo) -> Void
    @Environment(\.useLightContentOnIslandPanel) private var lightOnDarkIsland

    /// 索引导航条内指针位置（与 `alphabetIndex` 坐标空间一致，原点在左上）。
    @State private var indexPointerLocation: CGPoint?
    @State private var letterCenterY: [String: CGFloat] = [:]

    private let columnCount = 4
    private let indexColumnWidth: CGFloat = 36
    /// 固定行高，避免缩放时 GeometryReader / Preference 抖动导致卡顿。
    private let indexRowHeight: CGFloat = 20
    /// Dock 式放大：中心最大额外缩放比例。
    private let dockMaxBoost: CGFloat = 0.78
    /// 指针两侧影响范围（pt），越大相邻字母跟着抬得越多。
    private let dockInfluenceRadius: CGFloat = 44

    private var emptySecondary: Color {
        lightOnDarkIsland ? Color.white.opacity(0.45) : Color.secondary
    }

    private var indexLetterColor: Color {
        lightOnDarkIsland ? Color.white.opacity(0.88) : Color.accentColor
    }

    private var groupedApps: [(String, [AppInfo])] {
        let grouped = Dictionary(grouping: apps) { app -> String in
            let first = app.pinyinFull.first.map { String($0).uppercased() } ?? "#"
            return first.range(of: "[A-Z]", options: .regularExpression) != nil ? first : "#"
        }
        let sorted = grouped.sorted { lhs, rhs in
            if lhs.key == "#" { return false }
            if rhs.key == "#" { return true }
            return lhs.key < rhs.key
        }
        return sorted
    }

    var body: some View {
        if apps.isEmpty {
            emptyView
        } else {
            ScrollViewReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedApps, id: \.0) { letter, sectionApps in
                                Section {
                                    sectionAppGrid(sectionApps: sectionApps)
                                    .padding(.horizontal, 16)
                                } header: {
                                    Text(letter)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(lightOnDarkIsland ? Color.white.opacity(0.65) : Color.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background {
                                            if lightOnDarkIsland {
                                                Color.white.opacity(0.08)
                                            } else {
                                                Color.clear.background(.ultraThinMaterial)
                                            }
                                        }
                                        .id(letter)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    alphabetIndexColumn(scrollProxy: proxy)
                        .frame(width: indexColumnWidth)
                }
                .onPreferenceChange(AlphabetIndexLetterYPreference.self) { letterCenterY = $0 }
            }
        }
    }

    @ViewBuilder
    private func sectionAppGrid(sectionApps: [AppInfo]) -> some View {
        if sectionApps.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            let rowCount = (sectionApps.count + columnCount - 1) / columnCount
            let apps = sectionApps
            VStack(alignment: .center, spacing: 16) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(0..<columnCount, id: \.self) { col in
                            let idx = row * columnCount + col
                            Group {
                                if idx < apps.count {
                                    AppItemView(app: apps[idx])
                                        .onTapGesture { onAppTap(apps[idx]) }
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func alphabetIndexColumn(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(groupedApps.enumerated()), id: \.element.0) { _, element in
                let letter = element.0
                let scale = dockScale(forLetterCenterY: letterCenterY[letter])
                Text(letter)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(indexLetterColor)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: indexColumnWidth - 4, height: indexRowHeight)
                    .contentShape(Rectangle())
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: AlphabetIndexLetterYPreference.self,
                                value: [letter: g.frame(in: .named("alphabetIndex")).midY]
                            )
                        }
                    )
                    .compositingGroup()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scrollProxy.scrollTo(letter, anchor: .top)
                        }
                    }
                    .zIndex(Double(scale))
            }
        }
        .padding(.trailing, 2)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(width: indexColumnWidth)
        .coordinateSpace(name: "alphabetIndex")
        .onContinuousHover(coordinateSpace: .named("alphabetIndex")) { phase in
            switch phase {
            case .active(let location):
                indexPointerLocation = location
            case .ended:
                indexPointerLocation = nil
            }
        }
        .animation(
            .interactiveSpring(response: 0.11, dampingFraction: 0.88, blendDuration: 0.08),
            value: indexPointerLocation
        )
    }

    /// Apple Dock 风格：离指针越近缩放越大，smoothstep 过渡。
    private func dockScale(forLetterCenterY midY: CGFloat?) -> CGFloat {
        guard let midY else { return 1 }
        guard let p = indexPointerLocation else { return 1 }
        let d = abs(midY - p.y)
        let t = max(0, min(1, 1 - d / dockInfluenceRadius))
        let s = t * t * (3 - 2 * t)
        return 1 + dockMaxBoost * s
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 32))
                .foregroundColor(emptySecondary)
            Text("没有找到应用")
                .font(.system(size: 13))
                .foregroundColor(emptySecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
