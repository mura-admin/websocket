extension ChannelPipeline {
    /// Adds the supplied `WebSocket` to this `ChannelPipeline`.
    internal func add(webSocket: WebSocket) -> Future<Void> {
        let handler = WebSocketHandler(webSocket: webSocket)
        return add(handler: handler).then {
            
            return self.context(handler: handler).map { ctx in
                                
                handler.channelActive(ctx: ctx)
            }
        }
    }
}

// MARK: Private

/// Decodes `WebSocketFrame`s, forwarding to a `WebSocket`.
private final class WebSocketHandler: ChannelInboundHandler {
    /// See `ChannelInboundHandler`.
    typealias InboundIn = WebSocketFrame

    /// See `ChannelInboundHandler`.
    typealias OutboundOut = WebSocketFrame

    /// `WebSocket` to handle the incoming events.
    private var webSocket: WebSocket

    /// Creates a new `WebSocketEventDecoder`
    init(webSocket: WebSocket) {
        self.webSocket = webSocket
    }

    /// See `ChannelInboundHandler`.
    func channelActive(ctx: ChannelHandlerContext) {
        // connected
        ctx.fireChannelActive()
        webSocket.delegate?.webSocketDidConnect(socket: webSocket)
    }
    
    func channelInactive(ctx: ChannelHandlerContext) {
        // disconnected
        ctx.fireChannelInactive()
        webSocket.delegate?.webSocketDidDisconnect(socket: webSocket)
    }

    /// See `ChannelInboundHandler`.
    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        var frame = self.unwrapInboundIn(data)
        switch frame.opcode {
        case .connectionClose: receivedClose(ctx: ctx, frame: frame)
        case .ping: pong(ctx: ctx, frame: frame)
        case .unknownControl, .unknownNonControl: closeOnError(ctx: ctx)
        case .text:
            var data = frame.unmaskedData
            let text = data.readString(length: data.readableBytes) ?? ""
            webSocket.delegate?.webSocketDidReceiveText(socket: webSocket, text: text)
        case .binary:
            var data = frame.unmaskedData
            let binary = data.readData(length: data.readableBytes) ?? Data()
            webSocket.delegate?.webSocketDidReceiveBinary(socket: webSocket, data: binary)
        default:
            // We ignore all other frames.
            break
        }
    }

    /// See `ChannelInboundHandler`.
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        webSocket.delegate?.webSocketDidCaughtError(socket: webSocket, error: error)
    }

    /// Closes gracefully.
    private func receivedClose(ctx: ChannelHandlerContext, frame: WebSocketFrame) {
        /// Parse the close frame.
        var data = frame.unmaskedData
        if let closeCode = data.readInteger(as: UInt16.self)
            .map(Int.init)
            .flatMap(WebSocketErrorCode.init(codeNumber:))
        {
            webSocket.delegate?.webSocketDidReceiveClose(socket: webSocket, code: closeCode)
        } else {
            webSocket.delegate?.webSocketDidReceiveClose(socket: webSocket, code: nil)
        }

        // Handle a received close frame. In websockets, we're just going to send the close
        // frame and then close, unless we already sent our own close frame.
        if webSocket.isClosed {
            // Cool, we started the close and were waiting for the user. We're done.
            ctx.close(promise: nil)
        } else {
            // This is an unsolicited close. We're going to send a response frame and
            // then, when we've sent it, close up shop. We should send back the close code the remote
            // peer sent us, unless they didn't send one at all.
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: webSocket.mode.maskKey(), data: data)
            _ = ctx.writeAndFlush(wrapOutboundOut(closeFrame)).always {
                _ = ctx.close(promise: nil)
            }
        }
    }

    /// Sends a pong frame in response to ping.
    private func pong(ctx: ChannelHandlerContext, frame: WebSocketFrame) {
        var frameData = frame.data
        let maskingKey = frame.maskKey

        if let maskingKey = maskingKey {
            frameData.webSocketUnmask(maskingKey)
        }

        let responseFrame = WebSocketFrame(fin: true, opcode: .pong, maskKey: webSocket.mode.maskKey(), data: frameData)
        ctx.writeAndFlush(self.wrapOutboundOut(responseFrame), promise: nil)
    }

    /// Closes the connection with error frame.
    private func closeOnError(ctx: ChannelHandlerContext) {
        // We have hit an error, we want to close. We do that by sending a close frame and then
        // shutting down the write side of the connection.
        var data = ctx.channel.allocator.buffer(capacity: 2)
        let error = WebSocketErrorCode.protocolError
        data.write(webSocketErrorCode: error)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: webSocket.mode.maskKey(), data: data)
        _ = ctx.writeAndFlush(self.wrapOutboundOut(frame)).then {
            ctx.close(mode: .output)
        }
        webSocket.isClosed = true
    }
}
