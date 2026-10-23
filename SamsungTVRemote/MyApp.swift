import SwiftUI

@main struct MyApp: App {
    private let tv = SamsungTVClient.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tv)
                .preferredColorScheme(.dark)
        }
    }
}
