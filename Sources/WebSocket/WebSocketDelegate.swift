import Foundation

public protocol WebSocketDelegate: class {
    func webSocketDidConnect(socket: WebSocket)
    func webSocketDidDisconnect(socket: WebSocket)
    func webSocketDidReceiveText(socket: WebSocket, text: String)
    func webSocketDidReceiveBinary(socket: WebSocket, data: Data)
    func webSocketDidReceiveClose(socket: WebSocket, code: WebSocketErrorCode?)
    func webSocketDidCaughtError(socket: WebSocket, error: Error)
}
