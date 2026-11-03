import Foundation
import Security

extension KeychainClient {
  /// The live Keychain.
  ///
  /// Items are generic passwords in the data protection keychain, readable after the first unlock
  /// so a widget or extension can read them while the device is locked. A synchronizable item goes
  /// to the iCloud Keychain; any other never leaves this device, not even in a backup.
  public static let security = KeychainClient(
    add: { key, data in
      var query = baseQuery(key)
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = accessibility(key)
      return SecItemAdd(query as CFDictionary, nil)
    },
    update: { key, data in
      // Also moves an item stored before the accessibility was this one.
      let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: accessibility(key),
      ]
      return SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
    },
    read: { key in
      var query = baseQuery(key)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      return KeychainReadResult(status: status, data: result as? Data)
    },
    delete: { key in
      SecItemDelete(baseQuery(key) as CFDictionary)
    }
  )

  /// iCloud Keychain refuses the "this device only" classes, so a synchronizable item uses the
  /// same class without the restriction.
  private static func accessibility(_ key: KeychainItemKey) -> CFString {
    key.synchronizable
      ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
  }

  private static func baseQuery(_ key: KeychainItemKey) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: key.service,
      kSecAttrAccount as String: key.account,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: key.synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
    ]
    if let accessGroup = key.accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }
}
