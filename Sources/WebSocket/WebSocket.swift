import Crypto
/// Represents a client connected via WebSocket protocol.
/// Use this to receive text/data frames and send responses.
///
///      ws.onText { ws, string in
///         ws.send(string.reversed())
///      }
///
public final class WebSocket: BasicWorker {
    
    /// Available WebSocket modes. Either `Client` or `Server`.
    public enum Mode {
        
        /// Uses socket in `Client` mode
        case client
        
        /// Uses socket in `Server` mode
        case server
        
        /// RFC 6455 Section 5.1
        /// To avoid confusing network intermediaries (such as intercepting proxies) and
        /// for security reasons that are further, a client MUST mask all frames that it
        /// sends to the server.
        /// The server MUST close the connection upon receiving a frame that is not masked.
        /// A server MUST NOT mask any frames that it sends to the client.
        /// A client MUST close a connection if it detects a masked frame.
        ///
        /// RFC 6455 Section 5.3
        /// The masking key is a 32-bit value chosen at random by the client.
        /// When preparing a masked frame, the client MUST pick a fresh masking
        /// key from the set of allowed 32-bit values.
        public func maskKey() -> WebSocketMaskingKey? {
            switch self {
            case .client:
                let buffer = try! CryptoRandom().generateData(count: 4)
                return WebSocketMaskingKey(buffer)
            case .server:
                return  nil
            }
        }
    }
    
    /// See `BasicWorker`.
    public var eventLoop: EventLoop {
        return channel.eventLoop
    }
    
    public let id = UUID()

    /// Outbound `WebSocketEventHandler`.
    private let channel: Channel
    
    /// `WebSocket` processing mode.
    private(set) public var mode: Mode
    
    /// To handle socket events.
    weak var delegate: WebSocketDelegate?

    /// Creates a new `WebSocket` using the supplied `Channel` and `Mode`.
    /// Use `httpProtocolUpgrader(...)` to create a protocol upgrader that can create `WebSocket`s.
    internal init(channel: Channel, mode: Mode, delegate: WebSocketDelegate) {
        self.channel = channel
        self.mode = mode
        self.delegate = delegate
        self.isClosed = false
    }
    

    // MARK: Send

    /// Sends text-formatted data to the connected client.
    ///
    ///     ws.onText { ws, string in
    ///         ws.send(string.reversed())
    ///     }
    ///
    /// - parameters:
    ///     - text: `String` to send as text-formatted data to the client.
    ///     - promise: Optional `Promise` to complete when the send is finished.
    public func send<S>(_ text: S, promise: Promise<Void>? = nil) where S: Collection, S.Element == Character {
        return send(text: String(text), promise: promise)
    }

    /// Sends binary-formatted data to the connected client.
    ///
    ///     ws.onText { ws, string in
    ///         ws.send([0x68, 0x69])
    ///     }
    ///
    /// - parameters:
    ///     - text: `Data` to send as binary-formatted data to the client.
    ///     - promise: Optional `Promise` to complete when the send is finished.
    public func send(_ binary: Data, promise: Promise<Void>? = nil) {
        return send(binary: binary, promise: promise)
    }

    /// Sends text-formatted data to the connected client.
    ///
    ///     ws.onText { ws, string in
    ///         ws.send(text: string.reversed())
    ///     }
    ///
    /// - parameters:
    ///     - text: `LosslessDataConvertible` to send as text-formatted data to the client.
    ///     - promise: Optional `Promise` to complete when the send is finished.
    public func send(text: LosslessDataConvertible, promise: Promise<Void>? = nil) {
        send(text, opcode: .text, promise: promise)
    }

    /// Sends binary-formatted data to the connected client.
    ///
    ///     ws.onText { ws, string in
    ///         ws.send(binary: [0x68, 0x69])
    ///     }
    ///
    /// - parameters:
    ///     - data: `LosslessDataConvertible` to send as binary-formatted data to the client.
    ///     - promise: Optional `Promise` to complete when the send is finished.
    public func send(binary: LosslessDataConvertible, promise: Promise<Void>? = nil) {
        send(binary, opcode: .binary, promise: promise)
    }

    // MARK: Close

    /// `true` if the `WebSocket` has been closed.
    public internal(set) var isClosed: Bool

    /// A `Future` that will be completed when the `WebSocket` closes.
    public var onClose: Future<Void> {
        return channel.closeFuture
    }

    /// Closes the `WebSocket`'s connection, disconnecting the client.
    ///
    /// - parameters:
    ///     - code: Optional `WebSocketCloseCode` to send before closing the connection.
    ///             If a code is provided, the WebSocket will wait until an acknowledgment is
    ///             received from the server before actually closing the connection.
    public func close(code: WebSocketErrorCode? = nil) {
        guard !isClosed else {
            return
        }
        self.isClosed = true
        if let code = code {
            sendClose(code: code)
        } else {
            channel.close(promise: nil)
        }
    }
    
    public func ping() {
        guard !isClosed else {
            return
        }
        let frame = WebSocketFrame(fin: true, opcode: .ping, data: channel.allocator.buffer(capacity: 0))
        send(frame, promise: nil)
    }

    // MARK: Private

    /// Private just send close code.
    private func sendClose(code: WebSocketErrorCode) {
        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.write(webSocketErrorCode: code)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
        send(frame, promise: nil)
    }

    /// Private send that accepts a raw `WebSocketOpcode`.
    private func send(_ data: LosslessDataConvertible, opcode: WebSocketOpcode, promise: Promise<Void>?) {
        guard !isClosed else { return }
        let data = data.convertToData()
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.write(bytes: data)
        let maskKey: WebSocketMaskingKey? = mode.maskKey()
        send(WebSocketFrame(fin: true, opcode: opcode, maskKey: maskKey, data: buffer), promise: promise)
    }

    /// Private send that accepts a raw `WebSocketFrame`.
    private func send(_ frame: WebSocketFrame, promise: Promise<Void>?) {
        channel.writeAndFlush(frame, promise: promise)
    }
}
