//
//  SharedPreferences.swift
//  OpenInTerminalCore
//
//  Created by Jianing Wang on 2026/11/18.
//  Copyright © 2026 Jianing Wang. All rights reserved.
//

import Foundation

/// Mirrors the preferences the Finder extension consumes.
///
/// The app group (`group.wang.jianing.app.OpenInTerminal`) can no longer carry
/// preferences from the main app to the extension: the main app is not
/// sandboxed, and cfprefsd rejects a non-sandboxed process' reads and writes of
/// an app-group container ("requires user-preference-read or file-read-data
/// sandbox access"). Every preference silently failed to persist, so the app
/// performed its first-time setup on every launch and the extension never saw a
/// default terminal or editor (which leaves its context menu empty).
///
/// Both processes can access the extension's Application Scripts directory (the
/// app already installs its AppleScripts there), so the app mirrors the shared
/// keys into a plist file that the extension loads when it needs them.
public enum SharedPreferences {

    /// Keys the Finder extension reads through `DefaultsManager`.
    private static let mirroredKeys = [
        DefaultsKeys.defaultTerminal._key,
        DefaultsKeys.defaultEditor._key,
        DefaultsKeys.hideContextMenuItems._key,
        DefaultsKeys.contextMenuUseSubmenu._key,
        DefaultsKeys.customMenuOptions._key,
        DefaultsKeys.customMenuApplyToToolbar._key,
        DefaultsKeys.customMenuApplyToContext._key,
        DefaultsKeys.customMenuIconOption._key,
        DefaultsKeys.pathEscapeOption._key,
        DefaultsKeys.kittyCommand._key,
        DefaultsKeys.neovimCommand._key,
        DefaultsKeys.gitkrakenCommand._key,
    ]

    private static let extensionBundleIdSuffix = ".OpenInTerminalFinderExtension"

    private static var isFinderExtension: Bool {
        return Bundle.main.bundleIdentifier?.hasSuffix(extensionBundleIdSuffix) ?? false
    }

    private static var fileName: String {
        return "SharedPreferences"
    }

    /// `$HOME/Library/Application Scripts/<extension bundle id>/SharedPreferences.plist`
    public static var fileURL: URL? {
        guard let scriptsURL = try? FileManager.default.url(for: .applicationScriptsDirectory,
                                                            in: .userDomainMask,
                                                            appropriateFor: nil,
                                                            create: true) else {
            return nil
        }

        let directory: URL
        if isFinderExtension {
            directory = scriptsURL
        } else {
            guard let appId = Bundle.main.bundleIdentifier else { return nil }
            directory = scriptsURL
                .deletingLastPathComponent()
                .appendingPathComponent(appId + extensionBundleIdSuffix)
        }
        return directory.appendingPathComponent(fileName).appendingPathExtension("plist")
    }

    private static var lastImportedDate: Date?

    /// Writes the mirrored preferences for the Finder extension to read.
    public static func export() {
        guard let url = fileURL else { return }

        var values: [String: Any] = [:]
        for key in mirroredKeys {
            if let value = Defaults.object(forKey: key) {
                values[key] = value
            }
        }

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            // Skip unchanged writes so the extension only reloads real changes.
            if let existing = try? Data(contentsOf: url), existing == data {
                return
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            logw("Failed to export shared preferences: \(error)")
        }
    }

    /// Refreshes the extension's own defaults from the exported file.
    public static func importIfNeeded() {
        guard let url = fileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              modificationDate != lastImportedDate else {
            return
        }
        lastImportedDate = modificationDate

        guard let data = try? Data(contentsOf: url),
              let values = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return
        }

        for (key, value) in values {
            Defaults.set(value, forKey: key)
        }
    }

}
