//
//  DeviceGate.swift
//  EmPoster
//
//  Locks EmPoster Pro to a single authorized iPhone (serial-number gated).
//
//  iOS hides the serial behind an Apple entitlement, so we try the channels
//  available to a TrollStore / sandbox-escaped app:
//    1. MGCopyAnswer("SerialNumber") from libMobileGestalt (works when the
//       process holds the MobileGestalt SPI entitlement, e.g. jailed setups)
//    2. "SerialNumber" / its hashed key "VasUgeSzVyHdB27g2XpN0g" inside the
//       MobileGestalt cache plist (readable via bad_query container access)
//
//  If the serial can't be read, the device is treated as UNAUTHORIZED (safe
//  default), so the Pro subscription stays hidden on every other iPhone.
//

import Foundation
import Darwin

enum DeviceGate {

    /// The only iPhone that is allowed to access the Pro subscription.
    static let authorizedSerial = "QRTJW3GMF2"

    /// Hashed MobileGestalt key for `SerialNumber`.
    private static let hashedSerialKey = "VasUgeSzVyHdB27g2XpN0g"

    // MARK: - Result

    private static var cachedAuthorized: Bool?

    /// Whether this device is the owner's iPhone (serial matches).
    static var isAuthorizedDevice: Bool {
        if let cachedAuthorized { return cachedAuthorized }

        let authorized = serialNumber
            .map { normalized($0) == normalized(authorizedSerial) }
            ?? false

        cachedAuthorized = authorized
        return authorized
    }

    /// Best-effort device serial. `nil` when iOS blocks the read.
    static var serialNumber: String? {
        if let cachedSerial { return cachedSerial }

        let serial: String? = {
            if let viaMG = mgCopyAnswerSerial(), isUsable(viaMG) { return viaMG }
            if let viaPlist = gestaltPlistSerial(), isUsable(viaPlist) { return viaPlist }
            return nil
        }()

        cachedSerial = serial
        return serial
    }

    private static var cachedSerial: String?

    // MARK: - Helpers

    private static func normalized(_ value: String) -> String {
        value
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// MGCopyAnswer returns "Error" for protected keys without the SPI entitlement.
    private static func isUsable(_ value: String) -> Bool {
        !value.isEmpty
            && value.caseInsensitiveCompare("Error") != .orderedSame
            && value.caseInsensitiveCompare("N/A") != .orderedSame
    }

    // MARK: - Serial sources

    /// Reads the serial through the private MobileGestalt SPI.
    private static func mgCopyAnswerSerial() -> String? {
        typealias MGCopyAnswerFn = @convention(c) (CFString, CFDictionary?) -> Unmanaged<CFTypeRef>?

        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "MGCopyAnswer") else { return nil }
        let fn = unsafeBitCast(symbol, to: MGCopyAnswerFn.self)

        guard let unmanaged = fn("SerialNumber" as CFString, nil) else { return nil }
        let value = unmanaged.takeRetainedValue()
        return value as? String
    }

    /// Reads the serial out of the MobileGestalt cache plist (bad_query access).
    private static func gestaltPlistSerial() -> String? {
        do {
            try MobileGestaltManager.shared.grantAccess()
        } catch {
            return nil
        }

        guard let plist = NSMutableDictionary(contentsOfFile: MobileGestaltManager.gestaltPath) else { return nil }
        guard let extra = plist["CacheExtra"] as? NSDictionary else { return nil }

        // Try the human-readable key first, then the hashed key.
        if let serial = extra["SerialNumber"] as? String, isUsable(serial) {
            return serial
        }
        if let serial = extra[hashedSerialKey] as? String, isUsable(serial) {
            return serial
        }
        return nil
    }
}