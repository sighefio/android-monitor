package com.androidmonitor.codec

data class CodecConfig(
    val width: Int,
    val height: Int,
    val fps: Int,
    val audioSampleRate: Int,
    val audioChannels: Int = 2
)
