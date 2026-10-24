import AppKit
import SwiftUI

/// Renders the real views with live data into PNG files, for the README and for checking
/// layout without clicking through the menu bar.
///
/// With Screen Recording permission, each view briefly appears in a window and macOS
/// captures it, so Liquid Glass renders exactly as it does in the app. Without it, views
/// render offscreen, where glass effects come out flat. `demo` swaps in sample data, so
/// published images show no one's real apps.
enum Screenshots {
    static func render(to directory: URL, demo: Bool) async -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return fail(error.localizedDescription)
        }

        let state = AppState()
        if demo {
            state.showDemoData()
        } else {
            await state.refreshAdminStatus()
            await state.refresh(includeApps: true)
        }

        let live = CGPreflightScreenCaptureAccess()
        let pages: [(name: String, isPanel: Bool, view: AnyView)] = [
            ("panel", true, AnyView(PanelView())),
            ("settings-general", false, AnyView(GeneralSettings().frame(width: 500))),
            ("settings-cleaning", false, AnyView(CleaningSettings().frame(width: 500))),
            ("settings-auto-clean", false, AnyView(AutoCleanSettings().frame(width: 500))),
            ("settings-about", false, AnyView(AboutSettings().frame(width: 500))),
        ]

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for page in pages {
                let url = directory.appending(path: "\(page.name)-\(suffix).png")
                let view = page.view.environment(state)
                let rendered = live
                    ? await captureOnScreen(view, isPanel: page.isPanel, appearance: appearance, to: url)
                    : await renderOffscreen(view, appearance: appearance, to: url)
                guard rendered else { return fail("could not render \(page.name)") }
                print(url.path(percentEncoded: false))
            }
        }
        return 0
    }

    private static func captureOnScreen(_ view: some View, isPanel: Bool, appearance: NSAppearance.Name, to url: URL) async -> Bool {
        let content = Group {
            if isPanel {
                // The glass stands in for the menu bar window's background. It sits on its own
                // backdrop, so it never picks up whatever happens to be behind it on screen.
                view.glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .padding(32)
                    .background(PanelBackdrop())
            } else {
                view.background(.background)
            }
        }
        let hosting = NSHostingView(rootView: content)
        // Each window becomes key for its capture, so buttons and switches show their accent
        // color, as they do in use. The window is non-activating, so the app in front stays
        // in front, but it does take keystrokes for about a second.
        let window = CapturePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.contentView = hosting

        try? await Task.sleep(for: .milliseconds(300))
        window.setContentSize(hosting.fittingSize)
        let visible = NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(NSPoint(x: visible.minX + 40, y: visible.minY + 40))
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))

        let result = await Shell.run("/usr/sbin/screencapture", ["-x", "-o", "-l", "\(window.windowNumber)", url.path])
        window.orderOut(nil)
        return result.succeeded && FileManager.default.fileExists(atPath: url.path)
    }

    private static func renderOffscreen(_ view: some View, appearance: NSAppearance.Name, to url: URL) async -> Bool {
        let hosting = NSHostingView(rootView: view.background(.background))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting

        // Let SwiftUI lay out, load data, and finish its first animations.
        try? await Task.sleep(for: .milliseconds(300))
        window.setContentSize(hosting.fittingSize)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(700))

        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        return 1
    }
}

private struct PanelBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors: [Color] = colorScheme == .dark
            ? [Color(red: 0.11, green: 0.16, blue: 0.36), Color(red: 0.24, green: 0.11, blue: 0.40)]
            : [Color(red: 0.80, green: 0.89, blue: 1.00), Color(red: 0.95, green: 0.83, blue: 0.98)]
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
