//
//  InputMonitor.swift
//  KeystrumAgent
//
//  Created by Andrew Finke on 12/29/25.
//

import Cocoa
import CoreGraphics
import KeystrumCore

/// Represents a single input event to be batched for database write
struct InputEvent: Sendable {
    let code: Int64
    let timestamp: Double
    let eventType: String
    let modifiers: Int64
    let bundleId: String?
    let windowTitle: String?
    let character: String?
    let flightTime: Double?
    let dwellTime: Double?
    let mouseX: Double?
    let mouseY: Double?
    let sessionId: String
}

final class InputMonitor: @unchecked Sendable {
    static let shared = InputMonitor()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State for calculations
    private var lastKeyDownTime: Double = 0
    private var keyDownTimes: [Int64: Double] = [:]
    private var currentSessionId: String = UUID().uuidString
    private var lastActivityTime: Double = 0
    private let sessionTimeoutSeconds: Double = 30.0

    // Batching - uses shared config from KeystrumConfig.Batching
    private var eventQueue: [InputEvent] = []
    private let queueLock = NSLock()
    private var lastBatchTime: Double = 0
    private var lastDashboardHeartbeat: Double = 0

    /// Current batching mode based on dashboard activity
    private enum BatchMode: String {
        case fast   // Dashboard actively viewing
        case slow   // Dashboard recently active
        case idle   // Dashboard hasn't been seen in a while
    }

    private var currentBatchMode: BatchMode {
        let timeSinceHeartbeat = Date().timeIntervalSince1970 - lastDashboardHeartbeat
        if timeSinceHeartbeat < KeystrumConfig.Batching.activeThreshold {
            return .fast
        } else if timeSinceHeartbeat < KeystrumConfig.Batching.idleThreshold {
            return .slow
        } else {
            return .idle
        }
    }

    private var currentBatchSize: Int {
        switch currentBatchMode {
        case .fast: return KeystrumConfig.Batching.fastBatchSize
        case .slow: return KeystrumConfig.Batching.slowBatchSize
        case .idle: return KeystrumConfig.Batching.idleBatchSize
        }
    }

    private var currentBatchInterval: Double {
        switch currentBatchMode {
        case .fast: return KeystrumConfig.Batching.fastBatchInterval
        case .slow: return KeystrumConfig.Batching.slowBatchInterval
        case .idle: return KeystrumConfig.Batching.idleBatchInterval
        }
    }

    private init() {
        Log.sessionStarted(id: currentSessionId)
        setupDashboardListener()
    }

    private func setupDashboardListener() {
        DistributedNotificationCenter.default().addObserver(
            forName: KeystrumConfig.dashboardActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastDashboardHeartbeat = Date().timeIntervalSince1970
        }
    }

    // Callback for CGEventTap
    private let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        let monitor = InputMonitor.shared
        let timestamp = Date().timeIntervalSince1970
        let modifierFlags = event.flags.rawValue

        let keyCode = (type == .keyDown || type == .keyUp) ? event.getIntegerValueField(.keyboardEventKeycode) : 0

        // Session management
        if monitor.lastActivityTime > 0 && (timestamp - monitor.lastActivityTime) > monitor.sessionTimeoutSeconds {
            let oldSession = monitor.currentSessionId
            monitor.currentSessionId = UUID().uuidString
            Log.sessionTimeout(oldId: oldSession, newId: monitor.currentSessionId, idleSeconds: timestamp - monitor.lastActivityTime)
        }
        monitor.lastActivityTime = timestamp

        // Get active app and window
        var currentApp: String?
        var currentTitle: String?
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            currentApp = frontApp.bundleIdentifier
            currentTitle = monitor.getWindowTitle(for: frontApp)
        }

        // Handle Mouse Events
        if type == .leftMouseDown || type == .rightMouseDown {
            let location = event.location
            let eventType = (type == .leftMouseDown) ? "leftClick" : "rightClick"

            Log.click(type: eventType, x: location.x, y: location.y, app: currentApp)

            let inputEvent = InputEvent(
                code: 0,
                timestamp: timestamp,
                eventType: eventType,
                modifiers: Int64(modifierFlags),
                bundleId: currentApp,
                windowTitle: currentTitle,
                character: nil,
                flightTime: nil,
                dwellTime: nil,
                mouseX: location.x,
                mouseY: location.y,
                sessionId: monitor.currentSessionId
            )
            monitor.queueEvent(inputEvent)
            return Unmanaged.passRetained(event)
        }

        // Handle Keyboard Events
        if type == .keyDown {
            let flightTime = monitor.lastKeyDownTime > 0 ? (timestamp - monitor.lastKeyDownTime) : nil
            monitor.lastKeyDownTime = timestamp
            monitor.keyDownTimes[keyCode] = timestamp

            // Resolve character
            var charString: String?
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            if length > 0 {
                charString = String(utf16CodeUnits: chars, count: length)
            }

            Log.keyDown(code: keyCode, char: charString, app: currentApp, flightTime: flightTime)

            let inputEvent = InputEvent(
                code: keyCode,
                timestamp: timestamp,
                eventType: "keyDown",
                modifiers: Int64(modifierFlags),
                bundleId: currentApp,
                windowTitle: currentTitle,
                character: charString,
                flightTime: flightTime,
                dwellTime: nil,
                mouseX: nil,
                mouseY: nil,
                sessionId: monitor.currentSessionId
            )
            monitor.queueEvent(inputEvent)

        } else if type == .keyUp {
            var dwellTime: Double?
            if let downTime = monitor.keyDownTimes[keyCode] {
                dwellTime = timestamp - downTime
                monitor.keyDownTimes.removeValue(forKey: keyCode)
            }

            Log.keyUp(code: keyCode, dwellTime: dwellTime)

            let inputEvent = InputEvent(
                code: keyCode,
                timestamp: timestamp,
                eventType: "keyUp",
                modifiers: Int64(modifierFlags),
                bundleId: currentApp,
                windowTitle: currentTitle,
                character: nil,
                flightTime: nil,
                dwellTime: dwellTime,
                mouseX: nil,
                mouseY: nil,
                sessionId: monitor.currentSessionId
            )
            monitor.queueEvent(inputEvent)
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Batching

    private func queueEvent(_ event: InputEvent) {
        queueLock.lock()
        eventQueue.append(event)
        let queueCount = eventQueue.count
        let batchSize = currentBatchSize
        let batchInterval = currentBatchInterval
        let shouldFlush = queueCount >= batchSize ||
            (Date().timeIntervalSince1970 - lastBatchTime) > batchInterval
        queueLock.unlock()

        if shouldFlush {
            let reason = queueCount >= batchSize ? "batch_size(\(batchSize))" : "interval(\(Int(batchInterval))s)"
            flushQueue(reason: reason)
        }
    }

    private func flushQueue(reason: String) {
        queueLock.lock()
        guard !eventQueue.isEmpty else {
            queueLock.unlock()
            return
        }

        let eventsToWrite = eventQueue
        eventQueue = []
        lastBatchTime = Date().timeIntervalSince1970
        queueLock.unlock()

        Log.batchFlush(reason: reason)

        Task {
            let startTime = Date().timeIntervalSince1970

            // Convert InputEvent to tuple format for DatabaseManager
            let tuples = eventsToWrite.map { e in
                (code: e.code, time: e.timestamp, event: e.eventType, mods: e.modifiers,
                 app: e.bundleId, title: e.windowTitle, char: e.character,
                 fTime: e.flightTime, dTime: e.dwellTime,
                 mouseX: e.mouseX, mouseY: e.mouseY, session: e.sessionId)
            }

            await DatabaseManager.shared.logBatch(events: tuples)
            let duration = Date().timeIntervalSince1970 - startTime
            Log.batchWrite(count: eventsToWrite.count, duration: duration)

            // Post notification for dashboard refresh
            if eventsToWrite.count >= 10 {
                DistributedNotificationCenter.default().postNotificationName(
                    KeystrumConfig.dataUpdatedNotification,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        }
    }

    /// Flush any pending events (call on app termination)
    func flushPendingEvents() {
        queueLock.lock()
        let count = eventQueue.count
        queueLock.unlock()

        Log.appWillTerminate(pendingEvents: count)
        flushQueue(reason: "app_termination")
    }

    // MARK: - Window Title

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window)

        guard result == .success, let windowElement = window as! AXUIElement? else {
            return nil
        }

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title)

        guard titleResult == .success, let titleString = title as? String else {
            return nil
        }

        return titleString
    }

    // MARK: - Monitoring

    func startMonitoring() {
        Log.monitorStarted()

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventCallback,
            userInfo: nil
        ) else {
            Log.monitorFailed(reason: "failed to create event tap - check accessibility permissions")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Set up periodic flush timer (checks every second, flushes based on current mode)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let timeSinceLastBatch = Date().timeIntervalSince1970 - self.lastBatchTime
            if timeSinceLastBatch >= self.currentBatchInterval {
                self.flushQueue(reason: "timer(\(self.currentBatchMode.rawValue))")
            }
        }
    }

    func checkPermissions() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        if accessEnabled {
            Log.permissionsGranted()
        } else {
            Log.permissionsDenied()
        }
        return accessEnabled
    }
}
