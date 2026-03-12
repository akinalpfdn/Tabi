import Foundation
import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - TabiSettings

@Observable
final class TabiSettings {

    static let shared = TabiSettings()

    var hotkey: HotkeyConfig {
        didSet { saveHotkey() }
    }

    var launchAtStartup: Bool {
        didSet {
            saveLaunchAtStartup()
            updateLoginItem()
        }
    }

    // Set to true while the hotkey recorder is active so EventMonitor passes events through
    var isRecordingHotkey: Bool = false

    // MARK: - HotkeyConfig

    struct HotkeyConfig: Codable {
        var modifierFlags: UInt64  // CGEventFlags rawValue (single modifier only)
        var keyCode: Int
        var displayString: String

        static let `default` = HotkeyConfig(
            modifierFlags: CGEventFlags.maskAlternate.rawValue,
            keyCode: Int(kVK_Tab),
            displayString: "⌥Tab"
        )
    }

    // MARK: - Init

    private init() {
        if let data = UserDefaults.standard.data(forKey: "hotkeyConfig"),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            hotkey = config
        } else {
            hotkey = .default
        }

        if let stored = UserDefaults.standard.object(forKey: "launchAtStartup") as? Bool {
            launchAtStartup = stored
        } else {
            launchAtStartup = true  // default: on
        }
    }

    // MARK: - Persistence

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: "hotkeyConfig")
        }
    }

    private func saveLaunchAtStartup() {
        UserDefaults.standard.set(launchAtStartup, forKey: "launchAtStartup")
    }

    private func updateLoginItem() {
        if launchAtStartup {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Hotkey Display Helper

enum HotkeyHelper {

    static func displayString(nsFlags: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        let cgFlags = cgEventFlags(from: nsFlags)
        return displayString(cgFlags: cgFlags, keyCode: Int(keyCode))
    }

    static func displayString(cgFlags: CGEventFlags, keyCode: Int) -> String {
        var parts = ""
        if cgFlags.contains(.maskControl)  { parts += "⌃" }
        if cgFlags.contains(.maskAlternate) { parts += "⌥" }
        if cgFlags.contains(.maskShift)    { parts += "⇧" }
        if cgFlags.contains(.maskCommand)  { parts += "⌘" }
        parts += keyName(keyCode)
        return parts
    }

    static func cgEventFlags(from nsFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags = CGEventFlags()
        if nsFlags.contains(.option)  { flags.insert(.maskAlternate) }
        if nsFlags.contains(.command) { flags.insert(.maskCommand) }
        if nsFlags.contains(.control) { flags.insert(.maskControl) }
        if nsFlags.contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    // Maps CGKeyCode values to readable names
    static func keyName(_ code: Int) -> String {
        let table: [Int: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x19: "9", 0x1A: "7",
            0x1C: "8", 0x1D: "0", 0x1F: "O", 0x20: "U", 0x22: "I",
            0x23: "P", 0x24: "↩", 0x25: "L", 0x26: "J", 0x28: "K",
            0x2D: "N", 0x2E: "M", 0x30: "Tab", 0x31: "Space",
            0x33: "⌫", 0x35: "Esc",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return table[code] ?? "(\(code))"
    }
}
