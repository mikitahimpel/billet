import Design

/// What the action at the foot of a shop tile shows and does, from the price, the balance and whether the item is
/// owned. Short of coins it shows the shortfall, and the tap goes to Coins at that amount.
enum ShopPriceFace: Equatable {
    case buy(price: Int, was: Int?)
    case short(missing: Int)
    case owned
    case place
    case inRoom

    /// Where an owned piece is, for a piece the room can hold.
    enum Standing: Equatable {
        case notPlaceable, closet, room
    }

    enum Tap: Equatable {
        case buy
        case askForCoins(missing: Int)
        case none
        case place
    }

    init(price: Int, was: Int? = nil, coins: Int, owned: Bool, standing: Standing = .notPlaceable) {
        if owned {
            switch standing {
            case .notPlaceable: self = .owned
            case .closet: self = .place
            case .room: self = .inRoom
            }
        } else if coins < price {
            self = .short(missing: price - coins)
        } else {
            self = .buy(price: price, was: was.flatMap { $0 > price ? $0 : nil })
        }
    }

    var tap: Tap {
        switch self {
        case .buy: .buy
        case .short(let missing): .askForCoins(missing: missing)
        case .owned: .none
        case .place, .inRoom: .place
        }
    }

    var tileFace: TileButton.Face {
        switch self {
        case .buy(let price, let was): .price(price, was: was)
        case .short(let missing): .short(missing: missing)
        case .owned: .owned
        case .place: .place
        case .inRoom: .inRoom
        }
    }
}
