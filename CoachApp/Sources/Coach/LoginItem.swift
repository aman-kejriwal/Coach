import AppKit
import ServiceManagement

/// "Open Coach at login": registers the app itself as a login item, so it starts quietly in the
/// menu bar and keeps reminders up to date.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// Returns an error message, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return on
                ? "Couldn't add Coach to your login items: \(error.localizedDescription). Make sure Coach is in /Applications."
                : "Couldn't remove Coach from your login items: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// True when macOS launched Coach because it's a login item (not because you opened it).
    static func launchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
