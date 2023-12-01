//
//  DamusUserDefaults.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-25.
//

import Foundation

/// # DamusUserDefaults
///
/// This struct acts like a UserDefaults object, but is also capable of automatically mirroring values to a separate store.
///
/// It works by using a specific store container as the main source of truth, and by optionally mirroring values to a different container if needed.
///
/// This is useful when the data of a UserDefaults object needs to be accessible from another store container,
/// as it offers ways to automatically mirror information over a different container (e.g. When using app extensions)
///
/// Since it mirrors items instead of migrating them, this object can be used in a backwards compatible manner.
///
/// The easiest way to use this is to use `DamusUserDefaults.standard` as a drop-in replacement for `UserDefaults.standard`
/// Or, you can initialize a custom object with customizable stores.
struct DamusUserDefaults {
    
    // MARK: - Helper data structures
    
    enum Store: Equatable {
        case standard
        case shared
        case custom(UserDefaults)
        
        func get_user_defaults() -> UserDefaults? {
            switch self {
                case .standard:
                    return UserDefaults.standard
                case .shared:
                    return UserDefaults(suiteName: Constants.DAMUS_APP_GROUP_IDENTIFIER)
                case .custom(let user_defaults):
                    return user_defaults
            }
        }
    }
    
    enum DamusUserDefaultsError: Error {
        case cannot_initialize_user_defaults
        case cannot_mirror_main_user_defaults
    }
    
    // MARK: - Stored properties
    
    private let main: UserDefaults
    private let mirrors: [UserDefaults]
    
    // MARK: - Initializers
    
    init?(main: Store, mirror mirrors: [Store] = []) throws {
        guard let main_user_defaults = main.get_user_defaults() else { throw DamusUserDefaultsError.cannot_initialize_user_defaults }
        let mirror_user_defaults: [UserDefaults] = try mirrors.compactMap({ mirror_store in
            guard let mirror_user_default = mirror_store.get_user_defaults() else {
                throw DamusUserDefaultsError.cannot_initialize_user_defaults
            }
            guard mirror_store != main else {
                throw DamusUserDefaultsError.cannot_mirror_main_user_defaults
            }
            return mirror_user_default
        })
        
        self.main = main_user_defaults
        self.mirrors = mirror_user_defaults
    }
    
    // MARK: - Functions for feature parity with UserDefaults
    
    func string(forKey defaultName: String) -> String? {
        let value = self.main.string(forKey: defaultName)
        self.mirror(value, forKey: defaultName)
        return value
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        self.main.set(value, forKey: defaultName)
        self.mirror(value, forKey: defaultName)
    }
    
    func removeObject(forKey defaultName: String) {
        self.main.removeObject(forKey: defaultName)
        self.mirror_object_removal(forKey: defaultName)
    }
    
    func object(forKey defaultName: String) -> Any? {
        let value = self.main.object(forKey: defaultName)
        self.mirror(value, forKey: defaultName)
        return value
    }
    
    // MARK: - Mirroring utilities
    
    private func mirror(_ value: Any?, forKey defaultName: String) {
        for mirror in self.mirrors {
            mirror.set(value, forKey: defaultName)
        }
    }
    
    private func mirror_object_removal(forKey defaultName: String) {
        for mirror in self.mirrors {
            mirror.removeObject(forKey: defaultName)
        }
    }
}

// MARK: - Default convenience objects

/// # Convenience objects
///
/// - `DamusUserDefaults.standard`: will detect the bundle identifier and pick an appropriate object. You should generally use this one.
/// - `DamusUserDefaults.app`: stores things on its own container, and mirrors them to the shared container.
/// - `DamusUserDefaults.shared`: stores things on the shared container and does no mirroring
extension DamusUserDefaults {
    static let app: DamusUserDefaults = try! DamusUserDefaults(main: .standard, mirror: [.shared])!    // Since the underlying behavior is very static, the risk of crashing on force unwrap is low
    static let shared: DamusUserDefaults = try! DamusUserDefaults(main: .shared)!                      // Since the underlying behavior is very static, the risk of crashing on force unwrap is low
    static var standard: DamusUserDefaults {
        get {
            switch Bundle.main.bundleIdentifier {
                case Constants.MAIN_APP_BUNDLE_IDENTIFIER:
                    return Self.app
                case Constants.NOTIFICATION_EXTENSION_BUNDLE_IDENTIFIER:
                    return Self.shared
                default:
                    return Self.shared
            }
        }
    }
}
