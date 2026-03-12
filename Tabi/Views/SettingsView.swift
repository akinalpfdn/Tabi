import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - SettingsView

struct SettingsView: View {

    @State private var settings = TabiSettings.shared
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 20)

            // Shortcut row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcut")
                        .font(.body)
                    Text("Hold modifier + press key to switch windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                hotkeyButton
            }

            Divider()
                .padding(.vertical, 16)

            // Launch at startup row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at startup")
                        .font(.body)
                    Text("Start Tabi automatically when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $settings.launchAtStartup)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(24)
        .frame(width: 380)
        .onDisappear {
            stopRecording(save: false)
        }
    }

    // MARK: - Hotkey Button

    @ViewBuilder
    private var hotkeyButton: some View {
        Button {
            if isRecording {
                stopRecording(save: false)
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "Press a key…" : settings.hotkey.displayString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? .orange : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.orange.opacity(0.12) : Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isRecording ? Color.orange.opacity(0.6) : Color.primary.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        TabiSettings.shared.isRecordingHotkey = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Escape cancels recording
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording(save: false)
                return nil
            }

            let nsFlags = event.modifierFlags.intersection([.option, .command, .control, .shift])

            // Require at least one modifier (excluding Shift alone)
            let meaningfulModifiers = event.modifierFlags.intersection([.option, .command, .control])
            guard !meaningfulModifiers.isEmpty else { return event }

            let cgFlags = HotkeyHelper.cgEventFlags(from: nsFlags)
            let display = HotkeyHelper.displayString(cgFlags: cgFlags, keyCode: Int(event.keyCode))

            settings.hotkey = TabiSettings.HotkeyConfig(
                modifierFlags: cgFlags.rawValue,
                keyCode: Int(event.keyCode),
                displayString: display
            )

            stopRecording(save: true)
            return nil
        }
    }

    private func stopRecording(save: Bool) {
        isRecording = false
        TabiSettings.shared.isRecordingHotkey = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
