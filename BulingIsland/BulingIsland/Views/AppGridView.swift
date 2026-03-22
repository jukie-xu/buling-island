import SwiftUI

struct AppGridView: View {

    let apps: [AppInfo]
    let onAppTap: (AppInfo) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        if apps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("没有找到应用")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
