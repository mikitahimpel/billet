/// One page of the Inbox, newest first: `GET /v1/activity?before=&limit=`, without the items this
/// build can't read. `next` is the cursor
/// for the page after this one, `nil` on the last page. `head` is the newest item's cursor in the
/// whole list, on every page, `nil` while it is empty: send it as `upTo` to mark all read.
/// `unread` counts the partner's, the cat's and the store's items above the caller's read mark.
public struct ActivityResponse: Codable, Hashable, Sendable {
  public let items: [ActivityItem]
  public let next: String?
  public let head: String?
  public let unread: Int

  public init(items: [ActivityItem], next: String? = nil, head: String? = nil, unread: Int) {
    self.items = items
    self.next = next
    self.head = head
    self.unread = unread
  }

  private enum CodingKeys: String, CodingKey {
    case items
    case next
    case head
    case unread
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    items = try container.decodeLossyArray(ActivityItem.self, forKey: .items)
    next = try container.decodeOptionalKey(String.self, forKey: .next)
    head = try container.decodeOptionalKey(String.self, forKey: .head)
    unread = try container.decode(Int.self, forKey: .unread)
  }
}

/// `POST /v1/activity/read`: everything up to `upTo`, an opaque cursor, is read. The mark only
/// moves forward.
public struct MarkActivityReadRequest: Codable, Hashable, Sendable {
  public let upTo: String

  public init(upTo: String) {
    self.upTo = upTo
  }
}

/// The caller's unread count after marking read.
public struct ActivityUnreadResponse: Codable, Hashable, Sendable {
  public let unread: Int

  public init(unread: Int) {
    self.unread = unread
  }
}
