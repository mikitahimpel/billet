#if canImport(UIKit)
  import Design
  import Observation
  import SwiftUI
  import UIKit
  import WidgetUI

  // MARK: - Item sheet

  public struct ItemSheet: View {
    let item: ShopItem
    let state: any ShopHost

    @Environment(\.dismiss) private var dismiss

    @State private var turntable: any ItemPreview
    /// Still frame stays up until the 3D preview has really had a chance to draw.
    @State private var showsPlaceholder = true
    @State private var celebrating = false
    @State private var phase: ItemSheetMachine.State

    public init(item: ShopItem, state: any ShopHost) {
      self.item = item
      self.state = state
      _turntable = State(initialValue: state.makeItemPreview())
      _phase = State(
        initialValue: ItemSheetMachine.initial(owned: state.shop.owned.contains(item.id)))
    }

    private var cost: Int { state.shop.price(of: item) }
    private var affordable: Bool { state.shop.coins >= cost }
    private var owned: Bool { phase == .bought }
    private var isDeal: Bool { cost < item.price }

    public var body: some View {
      BilletSheet(item.name, size: .fit) {
        VStack(alignment: .leading, spacing: Space.l) {
          HStack(spacing: Space.s) {
            item.rarity.chip
            if isDeal, !owned {
              Chip(
                "−\(Int(((1 - Double(cost) / Double(item.price)) * 100).rounded()))%", style: .honey
              )
            } else if item.isNew, !owned {
              Chip("New", style: .honey)
            }
          }

          stage

          VStack(alignment: .leading, spacing: Space.m) {
            if let mood = item.mood {
              MochiReaction(name: state.petName, mood: mood, avatar: state.coatAvatarName)
            }
            Text(item.blurb)
              .font(.ourioCallout)
              .foregroundStyle(Ink.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          actions
        }
      }
      // A buy the coins don't cover opens the Coins sheet, which can't show over this one.
      .onChange(of: state.shop.coinsAsk) { _, ask in if ask != nil { send(.coinsAsked) } }
    }

    // MARK: Stage

    private var stage: some View {
      ZStack {
        // Same camera as the thumbnail (ItemTurntable.frame), so the still dissolves into the model
        // without the two showing side by side. Always on screen, so RealityKit is already drawing; the
        // model stays hidden until the turntable fades it in (ItemTurntable.isRevealed).
        turntable.scene(for: item)

        if let image = Thumbnails.image(item.thumbnail, maxPixels: 900) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .padding(.vertical, ItemStage.thumbnailInset)
            .opacity(showsPlaceholder ? 1 : 0)
            .allowsHitTesting(false)
        }

        // Horizontal drags spin the model; vertical ones are left to the sheet's own pan.
        HorizontalDragCatcher(
          onBegan: {
            turntable.isDragging = true
            reveal()
          },
          onChanged: { dx in turntable.spin(Float(dx) * 0.012) },
          onEnded: { turntable.isDragging = false }
        )
      }
      .frame(height: ItemStage.height)
      .wellSurface(.card)
      .corners(.card)
      .scaleEffect(celebrating ? 1.03 : 1)
      .accessibilityElement()
      .accessibilityLabel(item.name)
      .accessibilityHint("Drag sideways to turn it")
    }

    private func reveal() {
      // note: the still stays until the first drag or Preview, because the simulator puts RealityKit frames on
      // screen late and an automatic swap showed an empty stage; bring back a timed swap once checked on a device.
      guard showsPlaceholder, turntable.isDrawn else { return }
      // The model fades in under the still first, so lifting the still never uncovers an empty stage.
      turntable.isRevealed = true
      withAnimation(Motion.fade(0.3).delay(0.5)) { showsPlaceholder = false }
    }

    // MARK: Actions

    private var actions: some View {
      VStack(spacing: Space.s) {
        HStack(spacing: Space.s) {
          // A short word beside the cube, so the primary button keeps its label on one line on a small phone.
          Button(action: reveal) {
            Label("3D", systemImage: "cube")
              .lineLimit(1)
              .fixedSize()
          }
          .accessibilityLabel("Preview in 3D")
          .buttonStyle(SecondaryButtonStyle(fullWidth: false))
          .disabled(!showsPlaceholder || !turntable.isDrawn)
          .accessibilityHint("Drag the item to turn it")

          if owned {
            Button {
              send(.placeNowTapped)
            } label: {
              Label("Place now", systemImage: "house.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
          } else {
            Button(action: buy) { buyLabel.frame(maxWidth: .infinity) }
              .buttonStyle(PrimaryButtonStyle())
          }
        }
        if owned {
          Button("Not now") { send(.notNowTapped) }
            .font(.ourioCallout)
            .foregroundStyle(Ink.textSecondary)
            .frame(minHeight: Size.control)
            .accessibilityHint("Keeps it in your closet and closes this")
        } else if !affordable {
          Text(
            "Earn coins by answering today's question, keeping your streak and opening the daily gift."
          )
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity)
      .animation(Motion.spring(Motion.quick), value: owned)
    }

    private var buyLabel: some View {
      HStack(spacing: Space.s) {
        if affordable {
          Text("Buy for")
          CoinPrice(price: cost, was: isDeal ? item.price : nil)
        } else {
          Image(systemName: "plus.circle.fill")
          Text("Need \(state.shop.shortBy(cost)) more")
            .monospacedDigit()
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
    }

    private func send(_ event: ItemSheetMachine.Event) {
      let (next, outputs) = ItemSheetMachine.transition(phase, event)
      phase = next
      for output in outputs {
        switch output {
        case .openRoom: state.decorate(item.id)
        case .close: dismiss()
        }
      }
    }

    private func buy() {
      guard state.shop.buy(item) else { return }
      send(.bought)
      turntable.celebrate()
      withAnimation(.spring(duration: 0.3, bounce: 0.5)) { celebrating = true }
      withAnimation(Motion.spring(0.4).delay(0.3)) { celebrating = false }
    }
  }

  private struct MochiReaction: View {
    let name: String
    let mood: String
    let avatar: String

    var body: some View {
      HStack(spacing: Space.m) {
        Group {
          if let image = UIImage(named: avatar) {
            Image(uiImage: image).resizable().scaledToFill()
          } else {
            Image(systemName: "cat.fill").foregroundStyle(Color.honey)
          }
        }
        .frame(width: 40, height: 40)
        .clipShape(.circle)
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text("\(name) feels \(mood.lowercased())")
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
          Text(line)
            .font(.ourioCaption)
            .foregroundStyle(Ink.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(CardMetrics.padding)
      .cardSurface()
      .accessibilityElement(children: .combine)
    }

    private var line: String {
      switch mood {
      case "Curious": "\(name) will chase it all over the room."
      case "Rested": "\(name) naps better with it nearby."
      case "Happy": "\(name) purrs every time it's in the room."
      default: "\(name) notices it right away."
      }
    }
  }

  /// Declines vertical drags so the sheet keeps its own pull-to-dismiss.
  private struct HorizontalDragCatcher: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
      Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.backgroundColor = .clear
      let pan = UIPanGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.handle(_:)))
      pan.delegate = context.coordinator
      view.addGestureRecognizer(pan)
      return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
      context.coordinator.onBegan = onBegan
      context.coordinator.onChanged = onChanged
      context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var onBegan: () -> Void
      var onChanged: (CGFloat) -> Void
      var onEnded: () -> Void

      private var lastX: CGFloat = 0

      init(
        onBegan: @escaping () -> Void, onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
      ) {
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onEnded = onEnded
      }

      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
      }

      @objc func handle(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
          lastX = 0
          onBegan()
        case .changed:
          let x = pan.translation(in: pan.view).x
          onChanged(x - lastX)
          lastX = x
        case .ended, .cancelled, .failed:
          onEnded()
        default:
          break
        }
      }
    }
  }
#endif
