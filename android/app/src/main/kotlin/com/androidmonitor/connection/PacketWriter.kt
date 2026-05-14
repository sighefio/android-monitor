package com.androidmonitor.connection

class PacketWriter(private val manager: ConnectionManager) {
    fun touch(packet: TouchPacket) = manager.sendTouch(packet)
    fun key(packet: KeyPacket) = manager.sendKey(packet)
}
