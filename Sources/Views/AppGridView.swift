import SwiftUI

struct AppGridView: View {

    let apps: [AppInfo]
    let onAppTap: (AppInfo) -> Void
    @Environment(\.useLightContentOnIslandPanel) private var lightOnDarkIsland

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

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
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(apps) { app in
                        AppItemView(app: app)
                            .onTapGesture {
                                onAppTap(app)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
