/// Kódy kláves, které televize Samsung (Tizen) přijímá přes `ms.remote.control`.
enum TVKey: String {
    case power = "KEY_POWER"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case source = "KEY_SOURCE"
    case previousChannel = "KEY_PRECH"
    case digit0 = "KEY_0"
    case digit1 = "KEY_1"
    case digit2 = "KEY_2"
    case digit3 = "KEY_3"
    case digit4 = "KEY_4"
    case digit5 = "KEY_5"
    case digit6 = "KEY_6"
    case digit7 = "KEY_7"
    case digit8 = "KEY_8"
    case digit9 = "KEY_9"

    static func digit(_ value: Int) -> TVKey {
        [.digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9][value]
    }
}
