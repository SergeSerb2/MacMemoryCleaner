import AppKit
import SwiftUI

/// Renders the real views with live data into PNG files, for the README and for checking
/// layout without clicking through the menu bar.
///
/// With Screen Recording permission, each view briefly appears in a window and macOS
/// captures it, so Liquid Glass renders exactly as it does in the app. Without it, views
/// render offscreen, where glass effects come out flat.
enum Screenshots {
    static func render(to directory: URL) async -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return fail(error.localizedDescription)
        }

        let state = AppState()
        await state.refreshAdminStatus()
        await state.refresh(includeApps: true)

        let live = CGPreflightScreenCaptureAccess()
        let pages: [(name: String, isPanel: Bool, view: AnyView)] = [
            ("panel", true, AnyView(PanelView())),
            ("settings-general", false, AnyView(GeneralSettings().frame(width: 500))),
            ("settings-cleaning", false, AnyView(CleaningSettings().frame(width: 500))),
            ("settings-auto-clean", false, AnyView(AutoCleanSettings().frame(width: 500))),
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
                // Stand-in for the menu bar window's glass background.
                view.glassEffect(.regular, in: .rect(cornerRadius: 18))
            } else {
                view.background(.background)
            }
        }
        // The capture window never becomes key, so tell controls to draw as they do in the
        // open panel instead of greyed out.
        let hosting = NSHostingView(rootView: content.padding(isPanel ? 24 : 0).environment(\.appearsActive, true))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
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
        window.orderFrontRegardless()
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
