package com.androidmonitor

import com.androidmonitor.connection.KeyAction
import com.androidmonitor.connection.KeyModifiers
import com.androidmonitor.connection.KeyPacket
import com.androidmonitor.connection.PacketCodec
import com.androidmonitor.connection.PacketHeader
import com.androidmonitor.connection.PacketType
import com.androidmonitor.connection.Protocol
import com.androidmonitor.connection.TouchAction
import com.androidmonitor.connection.TouchPacket
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer

class PacketReaderTest {

    @Test
    fun headerRoundTrip() {
        val original = PacketHeader(
            type = PacketType.VIDEO_FRAME,
            flags = 0x07,
            length = 1234,
            sequence = 99L,
            timestampUs = 1_700_000_000_000_000L
        )
        val buf = ByteBuffer.allocate(Protocol.HEADER_SIZE)
        PacketCodec.writeHeader(buf, original)
        buf.flip()
        val decoded = PacketCodec.readHeader(buf)
        assertEquals(original.type, decoded.type)
        assertEquals(original.flags, decoded.flags)
        assertEquals(original.length, decoded.length)
        assertEquals(original.sequence, decoded.sequence)
        assertEquals(original.timestampUs, decoded.timestampUs)
    }

    @Test
    fun touchRoundTrip() {
        val packet = TouchPacket(TouchAction.MOVE, 1, 0.25f, 0.75f, 0.5f)
        val bytes = PacketCodec.encodeTouch(packet)
        assertEquals(14, bytes.size)
        val buf = ByteBuffer.wrap(bytes)
        assertEquals(TouchAction.MOVE.value, buf.get())
        assertEquals(1.toByte(), buf.get())
        assertEquals(0.25f, buf.float, 0f)
        assertEquals(0.75f, buf.float, 0f)
        assertEquals(0.5f, buf.float, 0f)
    }

    @Test
    fun keyRoundTrip() {
        val packet = KeyPacket(KeyAction.DOWN, KeyModifiers.SHIFT or KeyModifiers.META, 66, 0x1F600)
        val bytes = PacketCodec.encodeKey(packet)
        assertEquals(8, bytes.size)
        val expected = byteArrayOf(
            KeyAction.DOWN.value,
            (KeyModifiers.SHIFT or KeyModifiers.META),
            0x00, 0x42,
            0x00, 0x01, 0xF6.toByte(), 0x00
        )
        assertArrayEquals(expected, bytes)
    }

    private infix fun Byte.or(other: Byte): Byte = (this.toInt() or other.toInt()).toByte()
}
