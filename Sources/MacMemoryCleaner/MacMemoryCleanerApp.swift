import SwiftUI

@main
enum Main {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if CommandLineInterface.handles(arguments) {
            CommandLineInterface.run(arguments)
        }
        MacMemoryCleanerApp.main()
    }
}

struct MacMemoryCleanerApp: App {
    @State private var state: AppState
    @AppStorage(Preference.showUsageInMenuBar) private var showUsage: Bool

    init() {
        let state = AppState()
        state.start()
        _state = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(state)
        } label: {
            MenuBarLabel(state: state, showUsage: showUsage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

private struct MenuBarLabel: View {
    let state: AppState
    let showUsage: Bool

    var body: some View {
        // The outline chip next to a percentage reads as a battery, the filled one does not.
        let symbol = state.isCleaning ? "sparkles" : "memorychip.fill"
        let percent = Int((state.snapshot.usedFraction * 100).rounded())
        Group {
            if showUsage {
                Label("\(percent)%", systemImage: symbol)
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: symbol)
            }
        }
        .accessibilityLabel("Mac Memory Cleaner, memory used \(percent)%")
    }
}
