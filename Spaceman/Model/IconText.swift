//
//  IconText.swift
//  Spaceman
//
//  Created by Sasindu Jayasinghe on 6/12/20.
//

import Foundation

enum IconText: Int, CaseIterable {
    case noText = 0
    // Raw value 1 was "bare numbers" (removed); gap kept for UserDefaults compatibility.
    case numbers = 2
    case names = 3
    case numbersAndNames = 4

    var menuLabel: String {
        switch self {
        case .noText:           return String(localized: "No Text")
        case .numbers:         return String(localized: "Numbers")
        case .names:           return String(localized: "Names")
        case .numbersAndNames: return String(localized: "Numbers and Names")
        }
    }
}

/// Per-display-kind override of the icon text style.
/// The built-in screen and external monitors can each use their own style;
/// a nil override means "use the general icon text setting".
extension IconText {
    static let builtInOverrideKey = "iconTextBuiltIn"
    static let externalOverrideKey = "iconTextExternal"

    /// Raw value stored when no override is set.
    static let noOverrideRawValue = -1

    /// Resolves the text style for a space on the given display.
    static func resolve(default defaultText: IconText, displayID: String,
                        defaults: UserDefaults = .standard) -> IconText {
        guard !displayID.isEmpty else { return defaultText }
        let key = DisplayGeometryUtilities.isBuiltIn(displayUUID: displayID)
            ? builtInOverrideKey : externalOverrideKey
        guard let raw = defaults.object(forKey: key) as? Int else { return defaultText }
        return IconText(rawValue: raw) ?? defaultText
    }
}
