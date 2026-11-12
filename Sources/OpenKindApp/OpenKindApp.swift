import SwiftUI

@main struct OpenKindApp: App {
    var body: some Scene {
        WindowGroup { MainView() }
            .windowStyle(.hiddenTitleBar)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
