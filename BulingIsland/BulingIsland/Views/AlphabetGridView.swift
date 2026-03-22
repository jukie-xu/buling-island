import SwiftUI

struct AlphabetGridView: View {

    let apps: [AppInfo]
    let onAppTap: (AppInfo) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

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
                HStack(spacing: 0) {
                    // Main content
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedApps, id: \.0) { letter, sectionApps in
                                Section {
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(sectionApps) { app in
                                            AppItemView(app: app)
                                                .onTapGesture { onAppTap(app) }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                } header: {
                                    Text(letter)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.ultraThinMaterial)
                                        .id(letter)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Side alphabet index
                    VStack(spacing: 2) {
                        ForEach(groupedApps, id: \.0) { letter, _ in
                            Text(letter)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.accentColor)
                                .frame(width: 16, height: 14)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        proxy.scrollTo(letter, anchor: .top)
                                    }
                                }
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("没有找到应用")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
