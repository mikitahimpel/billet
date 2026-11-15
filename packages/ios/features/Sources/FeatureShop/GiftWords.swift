/// The words under the opened gift.
enum GiftWords {
  static func coins(_ amount: Int) -> String { amount == 1 ? "+1 coin" : "+\(amount) coins" }
}
