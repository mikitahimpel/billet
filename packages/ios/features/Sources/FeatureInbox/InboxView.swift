import Design
import SwiftUI
import Wire

/// The Inbox: what happened in the pair lately, grouped by day, newest first. Opening it marks
/// everything read for this person; rows that were new stay marked until it is opened again. A row
/// with a target opens it.
///
/// The app draws what only it knows: each actor's avatar, a mood's face, and the delivery notice
/// above the list.
public struct InboxView<Avatar: View, Face: View, Notice: View>: View {
  let model: InboxModel
  let names: InboxLine.Names
  /// Called with a row's target after the sheet has closed.
  let open: (ActivityTarget) -> Void
  let avatar: (ActivityActor) -> Avatar
  let face: (CheckInMood) -> Face
  let notice: (EdgeInsets) -> Notice
  /// False for a model that was opened already, as the gallery's.
  let opensModel: Bool
  /// The clock the days and the "4 minutes ago" lines are read against.
  let now: () -> Date

  @Environment(\.dismiss) private var dismiss

  public init(
    model: InboxModel, names: InboxLine.Names, opensModel: Bool = true,
    now: @escaping () -> Date = { .now },
    open: @escaping (ActivityTarget) -> Void,
    @ViewBuilder avatar: @escaping (ActivityActor) -> Avatar,
    @ViewBuilder face: @escaping (CheckInMood) -> Face,
    @ViewBuilder notice: @escaping (EdgeInsets) -> Notice
  ) {
    self.model = model
    self.names = names
    self.open = open
    self.avatar = avatar
    self.face = face
    self.notice = notice
    self.opensModel = opensModel
    self.now = now
  }

  public var body: some View {
    let layout = InboxLayout(model.sheet)
    BilletSheet("Inbox", size: layout.size, scrolls: layout.scrolls) {
      content
    }
    .task { if opensModel { await model.open() } }
  }

  @ViewBuilder private var content: some View {
    switch model.sheet {
    case .idle, .loading:
      placeholderList
    case .unpaired:
      EmptyState(
        symbol: "tray", title: "Nothing here yet",
        text: "Once your partner joins, what you both do with \(names.cat) shows up here.")
    case .failed:
      ErrorState("Couldn't load the Inbox", text: "Check your connection and try again.") {
        Task { await model.open() }
      }
    case .loaded(let page) where page.items.isEmpty:
      VStack(spacing: 0) {
        notice(EdgeInsets(top: 0, leading: 0, bottom: Space.l, trailing: 0))
        EmptyState(
          symbol: "tray", title: "All quiet",
          text: "Feeding \(names.cat), notes and gifts from you two will show up here.")
      }
    case .loaded(let page), .refreshing(let page), .stale(let page):
      list(page)
    }
  }

  private func list(_ page: InboxMachine.Page) -> some View {
    frame {
      ForEach(InboxDay.group(page.items, now: now()), id: \.day) { day in
        Section(day.title) {
          ForEach(day.items, id: \.id) { item in
            row(item, isNew: page.fresh.contains(item.id))
              .onAppear {
                if item.id == page.items.last?.id { model.loadMore() }
              }
          }
        }
        .listRowBackground(Ink.surface)
      }
    }
    .refreshable { await model.open() }
  }

  /// While the first page loads: the loaded list's frame, notice and section header, with still rows
  /// the size of real ones, so the page swaps rows in place instead of moving under the finger.
  private var placeholderList: some View {
    frame {
      Section("Today") {
        ForEach(0..<InboxPlaceholderRow.count, id: \.self) { _ in InboxPlaceholderRow() }
      }
      .listRowBackground(Ink.surface)
      .redacted(reason: .placeholder)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Loading the Inbox")
    }
  }

  private func frame(@ViewBuilder rows: () -> some View) -> some View {
    List { rows() }
      #if os(iOS)
        .listStyle(.insetGrouped)
      #endif
      .scrollContentBackground(.hidden)
      .scrollHeader {
        VStack(spacing: 0) {
          if case .stale = model.sheet { staleNotice }
          notice(EdgeInsets(top: Space.s, leading: Space.l, bottom: 0, trailing: Space.l))
        }
      }
  }

  private var staleNotice: some View {
    GroupedSection {
      Row(
        "Couldn't refresh", detail: "Showing what loaded last.", symbol: "wifi.exclamationmark",
        tint: Ink.destructive
      ) {
        RetryButton(compact: true) { Task { await model.open() } }
      }
    }
    .padding(.horizontal, Space.l)
    .padding(.top, Space.s)
  }

  @ViewBuilder private func row(_ item: ActivityItem, isNew: Bool) -> some View {
    let rowView = InboxRow(
      item: item, line: InboxLine(item, names: names), isNew: isNew, avatar: avatar(item.actor),
      face: face, now: now)
    if let target = item.target {
      Button {
        dismiss()
        open(target)
      } label: {
        HStack {
          rowView
          RowChevron()
        }
      }
      .buttonStyle(RowButtonStyle())
    } else {
      rowView
    }
  }
}

/// The Inbox for someone not connected yet.
public struct InboxSignedOut: View {
  let petName: String

  public init(petName: String) {
    self.petName = petName
  }

  public var body: some View {
    BilletSheet("Inbox", size: InboxLayout.short.size) {
      EmptyState(
        symbol: "tray", title: "Nothing here yet",
        text:
          "Once you're connected and your partner joins, what you both do with \(petName) shows up here."
      )
    }
  }
}

/// An Inbox row's frame: the avatar's side and the gap around the two lines.
private enum InboxRowMetrics {
  static let avatar: CGFloat = 40
  static let padding: CGFloat = Space.xs
}

/// A row while the Inbox loads: an avatar and the same two lines as a real row, redacted, never shimmering.
private struct InboxPlaceholderRow: View {
  static let count = 6

  var body: some View {
    HStack(spacing: Space.m) {
      Circle()
        .fill(Ink.surfaceRaised)
        .frame(width: InboxRowMetrics.avatar, height: InboxRowMetrics.avatar)
      VStack(alignment: .leading, spacing: 2) {
        Text("Someone did something lovely").font(.ourioCallout.weight(.medium))
        Text("A minute ago").font(.ourioCaption)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, InboxRowMetrics.padding)
  }
}

private struct InboxRow<Avatar: View, Face: View>: View {
  let item: ActivityItem
  let line: InboxLine
  let isNew: Bool
  let avatar: Avatar
  let face: (CheckInMood) -> Face
  let now: () -> Date

  var body: some View {
    HStack(spacing: Space.m) {
      avatar
        .frame(width: InboxRowMetrics.avatar, height: InboxRowMetrics.avatar)
        .overlay(alignment: .bottomTrailing) {
          if let mood = line.mood {
            face(mood)
              .frame(width: 24, height: 24)
              .offset(x: 5, y: 5)
          } else {
            Image(systemName: line.symbol)
              .font(.ourioMicro)
              .foregroundStyle(Ink.heroInk)
              .frame(width: 20, height: 20)
              .background(Color.honey, in: .circle)
              .overlay(Circle().stroke(Ink.surface, lineWidth: 1.5))
              .offset(x: 4, y: 4)
          }
        }
      VStack(alignment: .leading, spacing: 2) {
        Text(line.text)
          .font(.ourioCallout.weight(isNew ? .semibold : .medium))
          .foregroundStyle(Ink.text)
          .fixedSize(horizontal: false, vertical: true)
        TimelineView(.everyMinute) { _ in
          Text(Self.ago(date, now: now()))
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
        }
      }
      Spacer(minLength: 0)
      if isNew {
        Circle()
          .fill(Color.blushPink)
          .frame(width: 9, height: 9)
          .accessibilityLabel("New")
      }
    }
    .padding(.vertical, InboxRowMetrics.padding)
    .accessibilityElement(children: .combine)
  }

  private var date: Date { Date(timeIntervalSince1970: TimeInterval(item.at) / 1000) }

  /// "4 minutes ago", "yesterday".
  static func ago(_ date: Date, now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: date, relativeTo: now)
  }
}
