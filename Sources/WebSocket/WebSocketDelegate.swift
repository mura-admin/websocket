import Foundation

public protocol WebSocketDelegate: class {
    func webSocketDidReceiveText(socket: WebSocket, text: String)
    func webSocketDidReceiveBinary(socket: WebSocket, data: Data)
    func webSocketDidDisconnect(socket: WebSocket, code: WebSocketErrorCode?)
    func webSocketDidCaughtError(socket: WebSocket, error: Error)
}
