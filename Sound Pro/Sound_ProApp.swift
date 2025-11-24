import SwiftUI

@main
struct Sound_ProApp: App {
    var body: some Scene {
        MenuBarExtra("Sound Pro", systemImage: "headphones") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
