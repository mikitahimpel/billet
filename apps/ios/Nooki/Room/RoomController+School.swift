import SchoolInterface

extension RoomController {
    func school(_ move: SchoolMove) { current?.director?.school(move) }
}
