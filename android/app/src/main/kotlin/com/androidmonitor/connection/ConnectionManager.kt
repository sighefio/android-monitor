package com.androidmonitor.connection

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.nio.ByteBuffer

enum class ConnectionMode { WIFI, USB }

data class ConnectionTarget(val mode: ConnectionMode, val host: String, val port: Int = Protocol.DEFAULT_PORT)

data class StreamParams(
    val videoWidth: Int,
    val videoHeight: Int,
    val fps: Int,
    val audioSampleRate: Int
)

class ConnectionManager(
    private val client: TcpClient = TcpClient()
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val tag = "ConnectionManager"

    private val _state = MutableStateFlow<ConnectionEvent>(ConnectionEvent.Disconnected(null))
    val state: StateFlow<ConnectionEvent> = _state.asStateFlow()

    private val _streamParams = MutableStateFlow<StreamParams?>(null)
    val streamParams: StateFlow<StreamParams?> = _streamParams.asStateFlow()

    @Volatile private var pendingHandshake: HandshakeIntent? = null

    val packets: SharedFlow<IncomingPacket> get() = client.packets

    init {
        scope.launch {
            client.events.collect { event ->
                _state.value = event
                if (event is ConnectionEvent.Connected) {
                    pendingHandshake?.let { intent ->
                        sendHandshake(intent.width, intent.height, intent.fps)
                    }
                }
            }
        }
        scope.launch {
            client.packets.collect { packet ->
                when (packet.header.type) {
                    PacketType.HANDSHAKE_ACK -> handleHandshakeAck(packet.payload)
                    else -> {}
                }
            }
        }
    }

    fun connect(target: ConnectionTarget, deviceWidth: Int, deviceHeight: Int, deviceFps: Int) {
        val host = if (target.mode == ConnectionMode.USB) "127.0.0.1" else target.host
        pendingHandshake = HandshakeIntent(deviceWidth, deviceHeight, deviceFps)
        client.connect(host, target.port)
    }

    private data class HandshakeIntent(val width: Int, val height: Int, val fps: Int)

    fun selectDisplay(displayId: Int) {
        val json = JSONObject().put("display_id", displayId).toString()
        client.sendSelectDisplay(json.toByteArray(Charsets.UTF_8))
    }

    fun sendTouch(packet: TouchPacket) = client.sendTouch(packet)
    fun sendKey(packet: KeyPacket) = client.sendKey(packet)

    fun startPingLoop() {
        scope.launch {
            while (_state.value is ConnectionEvent.Connected) {
                val ts = System.nanoTime() / 1_000L
                val buf = ByteBuffer.allocate(8).putLong(ts).array()
                client.sendPing(buf)
                kotlinx.coroutines.delay(5_000)
            }
        }
    }

    fun disconnect() = client.disconnect()
    fun shutdown() = client.shutdown()

    private fun sendHandshake(width: Int, height: Int, fps: Int) {
        val json = JSONObject().apply {
            put("version", Protocol.VERSION)
            put("capabilities", org.json.JSONArray(listOf("h264", "aac")))
            put("screen_w", width)
            put("screen_h", height)
            put("screen_fps", fps)
        }
        client.sendHandshakeRequest(json.toString().toByteArray(Charsets.UTF_8))
    }

    private fun handleHandshakeAck(payload: ByteArray) {
        try {
            val json = JSONObject(String(payload, Charsets.UTF_8))
            _streamParams.value = StreamParams(
                videoWidth = json.getInt("video_w"),
                videoHeight = json.getInt("video_h"),
                fps = json.getInt("fps"),
                audioSampleRate = json.getInt("audio_sample_rate")
            )
        } catch (t: Throwable) {
            Log.e(tag, "handshake ack parse failed", t)
        }
    }
}
