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

  @Environment(\.dismiss) private var dismiss

  public init(
    model: InboxModel, names: InboxLine.Names, open: @escaping (ActivityTarget) -> Void,
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
  }

  public var body: some View {
    let layout = InboxLayout(model.sheet)
    BilletSheet("Inbox", size: layout.size, scrolls: layout.scrolls) {
      content
    }
    .task { await model.open() }
  }

  @ViewBuilder private var content: some View {
    switch model.sheet {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    case .unpaired:
      EmptyState(
        symbol: "tray", title: "Nothing here yet",
        text: "Once your partner joins, what you both do with \(names.cat) shows up here.")
    case .failed:
      EmptyState(
        symbol: "wifi.exclamationmark", title: "Couldn't load the Inbox",
        text: "Check your connection and try again."
      ) {
        SecondaryButton("Try Again", fullWidth: false) { Task { await model.open() } }
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
    List {
      ForEach(InboxDay.group(page.items), id: \.day) { day in
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
    #if os(iOS)
      .listStyle(.insetGrouped)
    #endif
    .scrollContentBackground(.hidden)
    .refreshable { await model.open() }
    .safeAreaInset(edge: .top, spacing: 0) {
      notice(EdgeInsets(top: Space.s, leading: Space.l, bottom: 0, trailing: Space.l))
    }
  }

  @ViewBuilder private func row(_ item: ActivityItem, isNew: Bool) -> some View {
    let rowView = InboxRow(
      item: item, line: InboxLine(item, names: names), isNew: isNew, avatar: avatar(item.actor),
      face: face)
    if let target = item.target {
      Button {
        dismiss()
        open(target)
      } label: {
        HStack {
          rowView
          Image(systemName: "chevron.right")
            .font(.ourioCaption.weight(.semibold))
            .foregroundStyle(Ink.textTertiary)
        }
      }
      .buttonStyle(.plain)
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

private struct InboxRow<Avatar: View, Face: View>: View {
  let item: ActivityItem
  let line: InboxLine
  let isNew: Bool
  let avatar: Avatar
  let face: (CheckInMood) -> Face

  var body: some View {
    HStack(spacing: 12) {
      avatar
        .frame(width: 40, height: 40)
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
        Text(date, format: .relative(presentation: .named))
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
      }
      Spacer(minLength: 0)
      if isNew {
        Circle()
          .fill(Color.blushPink)
          .frame(width: 9, height: 9)
          .accessibilityLabel("New")
      }
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private var date: Date { Date(timeIntervalSince1970: TimeInterval(item.at) / 1000) }
}
