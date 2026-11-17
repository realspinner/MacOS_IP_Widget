import Foundation

/// PlugInKit keeps third-party widget extensions disabled until they are
/// elected. LaunchServices registers the extension when the app starts, but a
/// freshly installed, ad-hoc signed build can stay in the "not elected" state
/// and never reach the widget gallery. Electing it once at launch makes the
/// first-run experience deterministic.
enum WidgetRegistration {
    static let widgetBundleIdentifier = "dev.spinner.ipwidget.widget"

    static func ensureWidgetEnabled() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-e", "use", "-i", widgetBundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
