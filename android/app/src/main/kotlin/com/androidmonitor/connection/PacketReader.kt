package com.androidmonitor.connection

import com.androidmonitor.codec.VideoDecoder
import com.androidmonitor.codec.AudioPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import java.nio.ByteBuffer

class PacketReader(
    private val packets: SharedFlow<IncomingPacket>,
    private val videoDecoder: VideoDecoder,
    private val audioPlayer: AudioPlayer
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun start() {
        scope.launch {
            packets.collect { packet ->
                when (packet.header.type) {
                    PacketType.VIDEO_FRAME -> handleVideo(packet)
                    PacketType.AUDIO_FRAME -> handleAudio(packet)
                    else -> {}
                }
            }
        }
    }

    fun stop() {
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }

    private fun handleVideo(packet: IncomingPacket) {
        if (packet.payload.size < 1) return
        val nalSlice = ByteBuffer.wrap(packet.payload, 1, packet.payload.size - 1)
        val isKeyframe = PacketFlags.has(packet.header.flags, PacketFlags.KEY_FRAME)
        videoDecoder.queueNAL(nalSlice, isKeyframe, packet.header.timestampUs)
    }

    private fun handleAudio(packet: IncomingPacket) {
        if (packet.payload.size < 2) return
        val payload = ByteBuffer.wrap(packet.payload, 2, packet.payload.size - 2)
        audioPlayer.queueAAC(payload, packet.header.timestampUs)
    }
}
