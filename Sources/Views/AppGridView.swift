import SwiftUI

struct AppGridView: View {

    let apps: [AppInfo]
    let onAppTap: (AppInfo) -> Void
    @Environment(\.useLightContentOnIslandPanel) private var lightOnDarkIsland

    private let columnCount = 4

    private var emptySecondary: Color {
        lightOnDarkIsland ? Color.white.opacity(0.45) : Color.secondary
    }

    var body: some View {
        if apps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32))
                    .foregroundColor(emptySecondary)
                Text("没有找到应用")
                    .font(.system(size: 13))
                    .foregroundColor(emptySecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                // 非惰性行布局（替代 LazyVGrid）；末行不足 4 个时仍占满四列网格，与上行列对齐。
                let rowCount = (apps.count + columnCount - 1) / columnCount
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
                .padding(.vertical, 8)
            }
        }
    }
}
