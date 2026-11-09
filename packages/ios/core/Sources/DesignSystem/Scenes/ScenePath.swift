import SwiftUI

/// The absolute SVG path subset `M L H V C Q Z`. Art is compile-time data, so an unknown command
/// is a programmer error; the test suite parses every drawing.
enum ScenePath {
  private static func arity(of command: Character) -> Int {
    switch command {
    case "M", "L": 2
    case "H", "V": 1
    case "Q": 4
    case "C": 6
    case "Z": 0
    default: preconditionFailure("Unsupported path command \(command)")
    }
  }

  static func parse(_ data: String) -> Path {
    var path = Path()
    var numbers: [CGFloat] = []
    var command: Character = "Z"
    var current = CGPoint.zero
    var token = ""

    func point(_ index: Int) -> CGPoint {
      CGPoint(x: numbers[index], y: numbers[index + 1])
    }

    func flushNumber() {
      guard !token.isEmpty else { return }
      guard let value = Double(token) else { preconditionFailure("Bad number \(token)") }
      numbers.append(CGFloat(value))
      token = ""
    }

    func draw() {
      while arity(of: command) > 0, numbers.count >= arity(of: command) {
        let used = arity(of: command)
        switch command {
        case "M":
          path.move(to: point(0))
          current = point(0)
          command = "L"
        case "L":
          path.addLine(to: point(0))
          current = point(0)
        case "H":
          current = CGPoint(x: numbers[0], y: current.y)
          path.addLine(to: current)
        case "V":
          current = CGPoint(x: current.x, y: numbers[0])
          path.addLine(to: current)
        case "Q":
          path.addQuadCurve(to: point(2), control: point(0))
          current = point(2)
        default:
          path.addCurve(to: point(4), control1: point(0), control2: point(2))
          current = point(4)
        }
        numbers.removeFirst(used)
      }
    }

    for character in data {
      switch character {
      case "M", "L", "H", "V", "C", "Q", "Z":
        flushNumber()
        draw()
        if character == "Z" {
          path.closeSubpath()
        }
        command = character
      case "-":
        flushNumber()
        draw()
        token = "-"
      case " ", ",", "\n":
        flushNumber()
        draw()
      default:
        token.append(character)
      }
    }
    flushNumber()
    draw()
    return path
  }
}
