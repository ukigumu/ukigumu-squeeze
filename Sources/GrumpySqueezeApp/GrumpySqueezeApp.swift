import SwiftUI

@main
struct GrumpySqueezeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 720)
    }
}
