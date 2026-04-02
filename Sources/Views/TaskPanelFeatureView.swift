import SwiftUI

struct TaskPanelFeatureView: View {
    let content: AnyView

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }
}
