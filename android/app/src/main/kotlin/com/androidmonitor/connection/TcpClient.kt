package com.androidmonitor.connection

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

sealed class ConnectionEvent {
    data object Connecting : ConnectionEvent()
    data object Connected : ConnectionEvent()
    data class Disconnected(val cause: Throwable?) : ConnectionEvent()
    data class Failed(val cause: Throwable) : ConnectionEvent()
}

data class IncomingPacket(val header: PacketHeader, val payload: ByteArray) {
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

class TcpClient {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sendQueue = Channel<ByteArray>(capacity = Channel.UNLIMITED)
    private val sequenceCounter = AtomicLong(0)
    private val isConnected = AtomicBoolean(false)
    private var socket: Socket? = null

    private val _events = MutableSharedFlow<ConnectionEvent>(replay = 1, extraBufferCapacity = 16)
    val events: SharedFlow<ConnectionEvent> = _events.asSharedFlow()

    private val _packets = MutableSharedFlow<IncomingPacket>(extraBufferCapacity = 256)
    val packets: SharedFlow<IncomingPacket> = _packets.asSharedFlow()

    fun connect(host: String, port: Int = Protocol.DEFAULT_PORT) {
        scope.launch {
            _events.emit(ConnectionEvent.Connecting)
            try {
                val sock = Socket().apply {
                    tcpNoDelay = true
                    keepAlive = true
                    receiveBufferSize = 1024 * 1024
                    sendBufferSize = 256 * 1024
                    connect(InetSocketAddress(host, port), 5_000)
                }
                socket = sock
                isConnected.set(true)
                _events.emit(ConnectionEvent.Connected)

                launch { writeLoop(sock) }
                readLoop(sock)
            } catch (t: Throwable) {
                _events.emit(ConnectionEvent.Failed(t))
            }
        }
    }

    fun disconnect() {
        scope.launch {
            isConnected.set(false)
            try { socket?.close() } catch (_: Throwable) {}
            _events.emit(ConnectionEvent.Disconnected(null))
        }
    }

    fun shutdown() {
        disconnect()
        scope.cancel()
    }

    fun sendTouch(packet: TouchPacket) {
        sendPayload(PacketType.TOUCH_EVENT, 0, PacketCodec.encodeTouch(packet))
    }

    fun sendKey(packet: KeyPacket) {
        sendPayload(PacketType.KEY_EVENT, 0, PacketCodec.encodeKey(packet))
    }

    fun sendHandshakeRequest(payload: ByteArray) {
        sendPayload(PacketType.HANDSHAKE_REQ, 0, payload)
    }

    fun sendSelectDisplay(payload: ByteArray) {
        sendPayload(PacketType.SELECT_DISPLAY, 0, payload)
    }

    fun sendPing(payload: ByteArray) {
        sendPayload(PacketType.PING, 0, payload)
    }

    private fun sendPayload(type: PacketType, flags: Byte, payload: ByteArray) {
        val header = PacketHeader(
            type = type,
            flags = flags,
            length = payload.size,
            sequence = sequenceCounter.incrementAndGet(),
            timestampUs = System.nanoTime() / 1_000L
        )
        val buf = ByteBuffer.allocate(Protocol.HEADER_SIZE + payload.size)
        PacketCodec.writeHeader(buf, header)
        buf.put(payload)
        sendQueue.trySend(buf.array())
    }

    private suspend fun writeLoop(sock: Socket) = withContext(Dispatchers.IO) {
        val out = sock.getOutputStream()
        try {
            while (isConnected.get()) {
                val bytes = sendQueue.receive()
                out.write(bytes)
                out.flush()
            }
        } catch (t: Throwable) {
            handleDisconnect(t)
        }
    }

    private suspend fun readLoop(sock: Socket) = withContext(Dispatchers.IO) {
        val input = sock.getInputStream()
        val headerBuf = ByteArray(Protocol.HEADER_SIZE)
        try {
            while (isConnected.get()) {
                if (!readFully(input, headerBuf, headerBuf.size)) break
                val header = PacketCodec.readHeader(ByteBuffer.wrap(headerBuf))
                val payload = ByteArray(header.length)
                if (header.length > 0 && !readFully(input, payload, payload.size)) break
                _packets.tryEmit(IncomingPacket(header, payload))
            }
            handleDisconnect(null)
        } catch (t: Throwable) {
            handleDisconnect(t)
        }
    }

    private suspend fun handleDisconnect(cause: Throwable?) {
        if (isConnected.compareAndSet(true, false)) {
            try { socket?.close() } catch (_: Throwable) {}
            _events.emit(ConnectionEvent.Disconnected(cause))
        }
    }

    private fun readFully(input: java.io.InputStream, buf: ByteArray, len: Int): Boolean {
        var read = 0
        while (read < len) {
            val n = input.read(buf, read, len - read)
            if (n < 0) return false
            read += n
        }
        return true
    }
}
