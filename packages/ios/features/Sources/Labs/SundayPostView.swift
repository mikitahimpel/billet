import DesignSystem
import FeatureInbox
import Ink
import SwiftUI

/// The page itself: the week's notes on paper, and how many went each way.
struct SundayPostPage: View {
  let post: SundayPost
  let images: [UUID: CGImage]
  let catName: String?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: 3)

  var body: some View {
    VStack(spacing: Spacing.medium) {
      VStack(spacing: Spacing.hair) {
        Text("The week of \(post.weekStart.formatted(.dateTime.day().month(.wide)))")
          .billetType(.heading)
        Text("\(catName ?? "The cat") brought you this")
          .billetType(.label)
      }
      .foregroundStyle(Palette.ink.color)
      LazyVGrid(columns: columns, spacing: Spacing.small) {
        ForEach(post.notes) { note in
          RoundedRectangle(cornerRadius: Radius.paper)
            .fill(Palette.paper.color)
            .overlay {
              if let image = images[note.id] {
                Image(decorative: image, scale: 1).resizable().scaledToFit().padding(4)
              }
            }
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: Palette.ink.color.opacity(0.25), radius: 2, y: 1)
        }
      }
      HStack(spacing: Spacing.small) {
        PawPrint().fill(Palette.inkGold.color).frame(width: 14, height: 16)
        Text("\(post.sent) sent · \(post.received) received")
          .billetType(.label)
          .foregroundStyle(Palette.ink.color)
      }
    }
    .padding(Spacing.large)
    .frame(width: 360)
    .background(Palette.paperTurned.color, in: .rect(cornerRadius: Radius.card))
  }
}

/// The Sunday post as a full-screen sheet, with a way to save or share the page as a picture.
struct SundayPostSheet: View {
  let post: SundayPost
  let catName: String?
  let onClose: () -> Void

  @State private var images: [UUID: CGImage] = [:]

  var body: some View {
    ZStack(alignment: .topLeading) {
      EveningBackground()
      VStack(spacing: Spacing.medium) {
        Spacer(minLength: Spacing.page)
        SundayPostPage(post: post, images: images, catName: catName)
          .lampGlow()
        shareButton
        Spacer(minLength: 0)
      }
      .padding(Spacing.medium)
      IconButton("xmark", label: "Close", action: onClose)
        .padding(Spacing.medium)
    }
    .task {
      let notes = post.notes
      images = await Task.detached {
        Dictionary(
          uniqueKeysWithValues: notes.compactMap { note in
            NoteImage.cgImage(of: note.strokes, side: 240).map { (note.id, $0) }
          })
      }.value
    }
  }

  @ViewBuilder private var shareButton: some View {
    #if canImport(UIKit)
      if let image = rendered {
        ShareLink(
          item: Image(uiImage: image),
          preview: SharePreview("The week's notes", image: Image(uiImage: image))
        ) {
          ButtonLabel("Save or share", rank: .primary)
        }
        .billetButton(.primary)
      }
    #endif
  }

  #if canImport(UIKit)
    @MainActor private var rendered: UIImage? {
      guard !images.isEmpty else { return nil }
      let renderer = ImageRenderer(
        content: SundayPostPage(post: post, images: images, catName: catName))
      renderer.scale = 3
      return renderer.uiImage
    }
  #endif
}

/// Home's row for the Sunday post: ready on a Sunday, a preview of the week so far on other days.
public struct SundayPostSection: View {
  private let notes: [NoteRecord]
  private let catName: String?

  @State private var opened: SundayPost?

  public init(notes: [NoteRecord], catName: String?) {
    self.notes = notes
    self.catName = catName
  }

  public var body: some View {
    TimelineView(.everyMinute) { context in
      let calendar = Calendar.current
      let sunday = SundayPost.isSunday(context.date, calendar: calendar)
      let post = SundayPost.page(
        from: notes, now: context.date, calendar: calendar, preview: !sunday)
      if let post, sunday || !notes.isEmpty {
        Button {
          opened = post
        } label: {
          ListRow(
            sunday ? "Sunday post" : "Sunday post, so far",
            subtitle: sunday
              ? "\(catName ?? "The cat") brought a page of your week."
              : "The page arrives on Sunday. Peek at this week."
          ) {
            PawPrint().fill(Palette.gold.color).frame(width: 22, height: 24)
              .accessibilityHidden(true)
          } trailing: {
            RowIcon("chevron.forward")
          }
        }
        .buttonStyle(RowButtonStyle())
        .card()
        .accessibilityIdentifier("sundayPost")
      }
    }
    #if os(iOS)
      .fullScreenCover(item: Binding(get: { opened.map(Wrapped.init) }, set: { opened = $0?.post }))
      { wrapped in
        SundayPostSheet(post: wrapped.post, catName: catName) { opened = nil }
      }
    #endif
  }

  private struct Wrapped: Identifiable {
    let post: SundayPost
    var id: Date { post.weekStart }
  }
}
