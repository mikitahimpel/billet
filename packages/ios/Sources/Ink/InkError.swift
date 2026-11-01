public enum InkError: Error, Hashable, Sendable {
  case invalidColor(String)
  case oddPointCount(strokeIndex: Int)
  case invalidParameters
  case overBudget(budget: Int, smallest: Int)
}
