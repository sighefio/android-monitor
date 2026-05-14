package com.androidmonitor.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.androidmonitor.codec.AudioPlayer
import com.androidmonitor.codec.CodecConfig
import com.androidmonitor.codec.VideoDecoder
import com.androidmonitor.connection.ConnectionEvent
import com.androidmonitor.connection.ConnectionManager
import com.androidmonitor.connection.ConnectionMode
import com.androidmonitor.connection.ConnectionTarget
import com.androidmonitor.connection.PacketReader
import com.androidmonitor.connection.PacketWriter
import com.androidmonitor.input.TouchHandler

@Composable
fun MainScreen(
    manager: ConnectionManager,
    videoDecoder: VideoDecoder,
    audioPlayer: AudioPlayer,
    deviceWidth: Int,
    deviceHeight: Int,
    deviceFps: Int,
    modifier: Modifier = Modifier
) {
    val state by manager.state.collectAsState()
    val stream by manager.streamParams.collectAsState()
    var packetReader by remember { mutableStateOf<PacketReader?>(null) }

    when (state) {
        is ConnectionEvent.Connected -> {
            val params = stream
            if (params != null) {
                val config = CodecConfig(
                    width = params.videoWidth,
                    height = params.videoHeight,
                    fps = params.fps,
                    audioSampleRate = params.audioSampleRate
                )
                if (packetReader == null) {
                    audioPlayer.configure(config)
                    val reader = PacketReader(manager.packets, videoDecoder, audioPlayer)
                    reader.start()
                    packetReader = reader
                }
                val touchHandler = remember { TouchHandler(PacketWriter(manager)) }
                DisplaySurface(
                    decoder = videoDecoder,
                    touchHandler = touchHandler,
                    config = config,
                    modifier = modifier.fillMaxSize()
                )
            }
        }
        else -> {
            ConnectScreen(
                onConnect = { mode: ConnectionMode, host: String ->
                    manager.connect(
                        ConnectionTarget(mode, host),
                        deviceWidth = deviceWidth,
                        deviceHeight = deviceHeight,
                        deviceFps = deviceFps
                    )
                    manager.startPingLoop()
                },
                modifier = modifier
            )
        }
    }
}
