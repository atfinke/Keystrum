//
//  Logger.swift
//  KeystrumAgent
//
//  Created by Andrew Finke on 12/29/25.
//

import Foundation
import os.log

/// Professional logging utility for KeystrumAgent
enum Log {
    private static let subsystem = "com.andrewfinke.KeystrumAgent"

    private static let monitor = Logger(subsystem: subsystem, category: "monitor")
    private static let database = Logger(subsystem: subsystem, category: "database")
    private static let session = Logger(subsystem: subsystem, category: "session")
    private static let app = Logger(subsystem: subsystem, category: "app")

    // MARK: - Monitor Events

    static func keyDown(code: Int64, char: String?, app: String?, flightTime: Double?) {
        let charDesc = char ?? "nil"
        let appDesc = app?.components(separatedBy: ".").last ?? "unknown"
        let ftDesc = flightTime.map { String(format: "%.0fms", $0 * 1000) } ?? "nil"
        monitor.debug("[KEY] code=\(code) char=\(charDesc) app=\(appDesc) flight=\(ftDesc)")
    }

    static func keyUp(code: Int64, dwellTime: Double?) {
        let dtDesc = dwellTime.map { String(format: "%.0fms", $0 * 1000) } ?? "nil"
        monitor.debug("[KEY] up code=\(code) dwell=\(dtDesc)")
    }

    static func click(type: String, x: Double, y: Double, app: String?) {
        let appDesc = app?.components(separatedBy: ".").last ?? "unknown"
        monitor.debug("[CLICK] \(type) at (\(Int(x)),\(Int(y))) app=\(appDesc)")
    }

    // MARK: - Session Events

    static func sessionStarted(id: String) {
        session.info("[SESSION] started id=\(id.prefix(8))...")
    }

    static func sessionTimeout(oldId: String, newId: String, idleSeconds: Double) {
        session.info("[SESSION] timeout after \(String(format: "%.0f", idleSeconds))s old=\(oldId.prefix(8))... new=\(newId.prefix(8))...")
    }

    // MARK: - Database Events

    static func batchWrite(count: Int, duration: Double) {
        database.info("[DB] wrote \(count) events in \(String(format: "%.1f", duration * 1000))ms")
    }

    static func batchQueued(count: Int) {
        database.debug("[DB] queue size: \(count)")
    }

    static func batchFlush(reason: String) {
        database.debug("[DB] flush triggered: \(reason)")
    }

    static func databaseError(_ error: Error) {
        database.error("[DB] error: \(error.localizedDescription)")
    }

    // MARK: - App Lifecycle

    static func monitorStarted() {
        app.info("[APP] input monitor started")
    }

    static func monitorFailed(reason: String) {
        app.error("[APP] monitor failed: \(reason)")
    }

    static func permissionsGranted() {
        app.info("[APP] accessibility permissions granted")
    }

    static func permissionsDenied() {
        app.warning("[APP] accessibility permissions denied")
    }

    static func appWillTerminate(pendingEvents: Int) {
        app.info("[APP] terminating, flushing \(pendingEvents) pending events")
    }

    // MARK: - Stats

    static func stats(totalKeys: Int, avgFlightTime: Double) {
        database.info("[STATS] keys=\(totalKeys) avgFlight=\(String(format: "%.0f", avgFlightTime * 1000))ms")
    }
}
