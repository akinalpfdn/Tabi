import SwiftUI
import AppKit
import ScreenCaptureKit
import ServiceManagement

// MARK: - TabiApp

@main
struct TabiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var viewModel: TabiViewModel?
    private var panel: OverlayPanel?
    private var permissionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()
        checkPermissionsAndStart()
        UpdateChecker.check(
            repo: "akinalpfdn/tabi",
            releasePageURL: URL(string: "https://github.com/akinalpfdn/tabi/releases/latest")!
        )
    }

    // MARK: - Permissions

    private func checkPermissionsAndStart() {
        let axTrusted = AXIsProcessTrusted()
        Task {
            let screenGranted = await checkScreenRecordingPermission()
            await MainActor.run {
                if axTrusted && screenGranted {
                    start()
                } else {
                    showPermissionWindow(accessibilityGranted: axTrusted, screenRecordingGranted: screenGranted)
                }
            }
        }
    }

    private func checkScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    private func showPermissionWindow(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tabi — Permissions Required"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        let view = PermissionView(
            accessibilityGranted: accessibilityGranted,
            screenRecordingGranted: screenRecordingGranted,
            onContinue: { [weak self, weak window] in
                window?.close()
                self?.checkPermissionsAndStart()
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
    }

    // MARK: - Start

    private func start() {
        let vm = TabiViewModel()
        viewModel = vm
        let p = OverlayPanel(viewModel: vm)
        panel = p
        observeVisibility(viewModel: vm, panel: p)
    }

    private func observeVisibility(viewModel: TabiViewModel, panel: OverlayPanel) {
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            Task { @MainActor in
                if viewModel.isVisible && !panel.isVisible {
                    panel.center()
                    panel.makeKeyAndOrderFront(nil)
                } else if !viewModel.isVisible && panel.isVisible {
                    panel.orderOut(nil)
                }
            }
        }
    }
}

// MARK: - PermissionView

struct PermissionView: View {
    let accessibilityGranted: Bool
    let screenRecordingGranted: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("Tabi needs two permissions")
                .font(.title3.bold())

            Text("These are required to detect your keyboard shortcut and show window thumbnails.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Detect Option+Tab keyboard shortcut",
                    granted: accessibilityGranted,
                    action: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                )

                PermissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    description: "Capture window thumbnails for the switcher",
                    granted: screenRecordingGranted,
                    action: {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        )
                    }
                )
            }

            Button("Continue") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!accessibilityGranted || !screenRecordingGranted)
        }
        .padding(30)
        .frame(width: 440)
    }
}

// MARK: - PermissionRow

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.bold())
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if !granted {
                Button("Grant Access") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
    }
}
