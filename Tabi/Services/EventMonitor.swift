import Foundation
import AppKit
import Carbon

// MARK: - EventMonitor

final class EventMonitor {

    var onOptionTab: ((_ reverse: Bool) -> Void)?
    var onOptionReleased: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSpaceShortcut: ((_ index: Int) -> Void)?   // -1 = All, 0 = Desktop 1, 1 = Desktop 2...

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Start / Stop

    func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("EventMonitor: Failed to create event tap — check Accessibility permission")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private var modifierHeld = false

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {

        // Pass all events through while user is recording a new hotkey
        if TabiSettings.shared.isRecordingHotkey {
            return Unmanaged.passUnretained(event)
        }

        let settings = TabiSettings.shared
        let targetModifier = CGEventFlags(rawValue: settings.hotkey.modifierFlags)
        let targetKeyCode = Int64(settings.hotkey.keyCode)

        if type == .flagsChanged {
            let flags = event.flags
            let wasHeld = modifierHeld
            modifierHeld = flags.contains(targetModifier)
            if wasHeld && !modifierHeld {
                DispatchQueue.main.async { self.onOptionReleased?() }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            if keyCode == targetKeyCode && flags.contains(targetModifier) {
                let reverse = flags.contains(.maskShift)
                DispatchQueue.main.async { self.onOptionTab?(reverse) }
                return nil  // swallow
            }

            // Space switching: ` for All, 1-9 for desktops (while modifier held)
            if modifierHeld {
                if keyCode == kVK_ANSI_Grave || keyCode == kVK_ISO_Section {
                    DispatchQueue.main.async { self.onSpaceShortcut?(-1) }
                    return nil
                }
                // kVK_ANSI_1 (0x12) through kVK_ANSI_9 (0x19) are not sequential,
                // so map them explicitly
                let digitKeyCodes: [Int64: Int] = [
                    Int64(kVK_ANSI_1): 0, Int64(kVK_ANSI_2): 1, Int64(kVK_ANSI_3): 2,
                    Int64(kVK_ANSI_4): 3, Int64(kVK_ANSI_5): 4, Int64(kVK_ANSI_6): 5,
                    Int64(kVK_ANSI_7): 6, Int64(kVK_ANSI_8): 7, Int64(kVK_ANSI_9): 8,
                ]
                if let desktopIndex = digitKeyCodes[keyCode] {
                    DispatchQueue.main.async { self.onSpaceShortcut?(desktopIndex) }
                    return nil
                }
            }

            if keyCode == kVK_Escape {
                DispatchQueue.main.async { self.onEscape?() }
                // don't swallow — let escape propagate
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
