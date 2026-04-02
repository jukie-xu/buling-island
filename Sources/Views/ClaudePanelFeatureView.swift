import SwiftUI

struct ClaudePanelFeatureView: View {
    let shouldPersistSessionHost: Bool
    let isLayerInteractive: Bool
    let panelContent: AnyView

    var body: some View {
        if shouldPersistSessionHost {
            panelContent
                .opacity(isLayerInteractive ? 1 : 0)
                .allowsHitTesting(isLayerInteractive)
        } else {
            panelContent
        }
    }
}
