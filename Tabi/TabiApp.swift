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
    private var onboardingWindow: NSWindow?
    private var toastWindow: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()
        checkPermissionsAndStart()
        UpdateChecker.check(
            repo: "akinalpfdn/tabi",
            releasePageURL: URL(string: "https://github.com/akinalpfdn/tabi/releases/latest")!
        )
    }

    // MARK: - Permission Flow

    private func checkPermissionsAndStart() {
        let axTrusted = AXIsProcessTrusted()
        Task {
            let screenGranted = await checkScreenRecordingPermission()
            await MainActor.run {
                if axTrusted && screenGranted {
                    startApp()
                } else if !axTrusted {
                    showOnboarding(step: .accessibility)
                } else {
                    showOnboarding(step: .screenRecording)
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

    private func startApp() {
        let vm = TabiViewModel()
        viewModel = vm
        let p = OverlayPanel(viewModel: vm)
        panel = p
        observeVisibility(viewModel: vm, panel: p)
        showWelcomeToastIfNeeded()
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

    // MARK: - Onboarding

    func showOnboarding(step: OnboardingStep) {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            window.level = .floating
            onboardingWindow = window
        }

        let view = OnboardingView(
            step: step,
            onOpenAccessibilitySettings: {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            },
            onAccessibilityGranted: { [weak self] in
                self?.showOnboarding(step: .screenRecording)
            },
            onOpenScreenRecordingSettings: {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                )
            }
        )

        onboardingWindow?.contentView = NSHostingView(rootView: view)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Welcome Toast

    private func showWelcomeToastIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "welcomeToastShown") else { return }
        UserDefaults.standard.set(true, forKey: "welcomeToastShown")
        showWelcomeToast()
    }

    private func showWelcomeToast() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 300
        let height: CGFloat = 64
        let margin: CGFloat = 16

        let frame = NSRect(
            x: screen.visibleFrame.maxX - width - margin,
            y: screen.visibleFrame.maxY - height - margin,
            width: width,
            height: height
        )

        let toast = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        toast.level = .floating
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.isReleasedWhenClosed = false
        toast.alphaValue = 0

        toast.contentView = NSHostingView(rootView: WelcomeToastView())
        toast.orderFront(nil)
        toastWindow = toast

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            toast.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                self?.toastWindow?.animator().alphaValue = 0
            }) {
                self?.toastWindow?.orderOut(nil)
                self?.toastWindow = nil
            }
        }
    }
}

// MARK: - Onboarding Step

enum OnboardingStep {
    case accessibility
    case screenRecording
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let step: OnboardingStep
    let onOpenAccessibilitySettings: () -> Void
    let onAccessibilityGranted: () -> Void
    let onOpenScreenRecordingSettings: () -> Void

    @State private var accessibilityCheckFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(step == .accessibility ? Color.accentColor : Color.accentColor.opacity(0.3))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(step == .screenRecording ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
            .padding(.top, 28)

            Spacer()

            if step == .accessibility {
                accessibilityStep
            } else {
                screenRecordingStep
            }

            Spacer()
        }
        .frame(width: 480, height: 420)
        .background(.windowBackground)
    }

    // MARK: Accessibility Step

    @ViewBuilder
    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                Text("Allow Accessibility Access")
                    .font(.title2.bold())

                VStack(spacing: 6) {
                    Text("Tabi uses Accessibility to detect your keyboard shortcut and switch windows.")
                        .foregroundStyle(.secondary)
                    Text("It cannot read your screen, keystrokes, or any other app's content.")
                        .foregroundStyle(.secondary)

                    Link("Verify on GitHub →", destination: URL(string: "https://github.com/akinalpfdn/tabi")!)
                        .font(.footnote)
                        .padding(.top, 2)
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            }

            VStack(spacing: 10) {
                Button {
                    accessibilityCheckFailed = false
                    onOpenAccessibilitySettings()
                } label: {
                    Label("Open Accessibility Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 280)

                Button("I've allowed it") {
                    if AXIsProcessTrusted() {
                        accessibilityCheckFailed = false
                        onAccessibilityGranted()
                    } else {
                        accessibilityCheckFailed = true
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(width: 280)

                if accessibilityCheckFailed {
                    Text("Permission not detected yet — make sure Tabi is checked and try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: accessibilityCheckFailed)
        }
        .padding(.horizontal, 48)
    }

    // MARK: Screen Recording Step

    @ViewBuilder
    private var screenRecordingStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                Text("Allow Screen Recording")
                    .font(.title2.bold())

                VStack(spacing: 6) {
                    Text("Tabi uses Screen Recording to show live window previews in the switcher.")
                        .foregroundStyle(.secondary)
                    Text("Nothing is recorded, stored, or transmitted anywhere.")
                        .foregroundStyle(.secondary)

                    Link("Verify on GitHub →", destination: URL(string: "https://github.com/akinalpfdn/tabi")!)
                        .font(.footnote)
                        .padding(.top, 2)
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            }

            VStack(spacing: 10) {
                Button {
                    onOpenScreenRecordingSettings()
                } label: {
                    Label("Open Screen Recording Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 300)

                Text("After allowing, macOS will ask you to quit and reopen Tabi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Welcome Toast

struct WelcomeToastView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tabi is running")
                    .font(.subheadline.bold())
                Text("Press your shortcut to switch windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
