package com.androidmonitor.connection

import java.nio.ByteBuffer
import java.nio.ByteOrder

object Protocol {
    const val MAGIC_0: Byte = 0xAD.toByte()
    const val MAGIC_1: Byte = 0x01.toByte()
    const val HEADER_SIZE: Int = 22
    const val MAX_PAYLOAD_SIZE: Int = 4 * 1024 * 1024
    const val VERSION: Int = 1
    const val DEFAULT_PORT: Int = 7878
}

enum class PacketType(val value: Byte) {
    HANDSHAKE_REQ(0x01),
    HANDSHAKE_ACK(0x02),
    HANDSHAKE_ERR(0x03),
    VIDEO_FRAME(0x10),
    AUDIO_FRAME(0x11),
    TOUCH_EVENT(0x20),
    KEY_EVENT(0x21),
    DISPLAY_LIST(0x30),
    SELECT_DISPLAY(0x31),
    PING(0x40),
    PONG(0x41),
    STREAM_PAUSE(0x50),
    STREAM_RESUME(0x51);

    companion object {
        private val byValue = entries.associateBy { it.value }
        fun fromValue(v: Byte): PacketType? = byValue[v]
    }
}

object PacketFlags {
    const val KEY_FRAME: Byte = 0x01
    const val FRAME_START: Byte = 0x02
    const val FRAME_END: Byte = 0x04
    const val COMPRESSED: Byte = 0x08

    fun has(flags: Byte, mask: Byte): Boolean = (flags.toInt() and mask.toInt()) != 0
}

enum class TouchAction(val value: Byte) {
    DOWN(0x00), MOVE(0x01), UP(0x02), CANCEL(0x03);

    companion object {
        fun fromValue(v: Byte): TouchAction? = entries.firstOrNull { it.value == v }
    }
}

enum class KeyAction(val value: Byte) {
    DOWN(0x00), UP(0x01);

    companion object {
        fun fromValue(v: Byte): KeyAction? = entries.firstOrNull { it.value == v }
    }
}

object KeyModifiers {
    const val SHIFT: Byte = 0x01
    const val CTRL: Byte = 0x02
    const val ALT: Byte = 0x04
    const val META: Byte = 0x08
}

data class PacketHeader(
    val type: PacketType,
    val flags: Byte,
    val length: Int,
    val sequence: Long,
    val timestampUs: Long
)

data class TouchPacket(
    val action: TouchAction,
    val pointerId: Byte,
    val xNorm: Float,
    val yNorm: Float,
    val pressure: Float
)

data class KeyPacket(
    val action: KeyAction,
    val modifiers: Byte,
    val androidKeycode: Short,
    val unicodeChar: Int
)

class ProtocolException(message: String) : RuntimeException(message)

object PacketCodec {
    fun writeHeader(buffer: ByteBuffer, header: PacketHeader) {
        buffer.order(ByteOrder.BIG_ENDIAN)
        buffer.put(Protocol.MAGIC_0)
        buffer.put(Protocol.MAGIC_1)
        buffer.put(header.type.value)
        buffer.put(header.flags)
        buffer.putInt(header.length)
        buffer.putLong(header.sequence)
        buffer.putLong(header.timestampUs)
    }

    fun readHeader(buffer: ByteBuffer): PacketHeader {
        if (buffer.remaining() < Protocol.HEADER_SIZE) throw ProtocolException("short header")
        buffer.order(ByteOrder.BIG_ENDIAN)
        val m0 = buffer.get(); val m1 = buffer.get()
        if (m0 != Protocol.MAGIC_0 || m1 != Protocol.MAGIC_1) {
            throw ProtocolException("invalid magic: ${m0.toInt() and 0xFF} ${m1.toInt() and 0xFF}")
        }
        val typeByte = buffer.get()
        val type = PacketType.fromValue(typeByte) ?: throw ProtocolException("unknown packet type $typeByte")
        val flags = buffer.get()
        val length = buffer.int
        if (length < 0 || length > Protocol.MAX_PAYLOAD_SIZE) {
            throw ProtocolException("payload too large: $length")
        }
        val sequence = buffer.long
        val ts = buffer.long
        return PacketHeader(type, flags, length, sequence, ts)
    }

    fun encodeTouch(packet: TouchPacket): ByteArray {
        val buf = ByteBuffer.allocate(14).order(ByteOrder.BIG_ENDIAN)
        buf.put(packet.action.value)
        buf.put(packet.pointerId)
        buf.putFloat(packet.xNorm)
        buf.putFloat(packet.yNorm)
        buf.putFloat(packet.pressure)
        return buf.array()
    }

    fun encodeKey(packet: KeyPacket): ByteArray {
        val buf = ByteBuffer.allocate(8).order(ByteOrder.BIG_ENDIAN)
        buf.put(packet.action.value)
        buf.put(packet.modifiers)
        buf.putShort(packet.androidKeycode)
        buf.putInt(packet.unicodeChar)
        return buf.array()
    }
}
