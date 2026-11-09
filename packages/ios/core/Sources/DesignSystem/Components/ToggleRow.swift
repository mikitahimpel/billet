import SwiftUI

public struct ToggleRow: View {
  private let title: String
  private let subtitle: String?
  @Binding private var isOn: Bool

  public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
    self.title = title
    self.subtitle = subtitle
    _isOn = isOn
  }

  public var body: some View {
    ListRow(title, subtitle: subtitle) {
      EmptyView()
    } trailing: {
      Toggle(title, isOn: $isOn)
        .labelsHidden()
        .tint(Palette.gold.color)
    }
    .accessibilityElement(children: .combine)
  }
}
