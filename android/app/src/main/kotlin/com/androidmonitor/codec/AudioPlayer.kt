package com.androidmonitor.codec

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

class AudioPlayer {
    private val tag = "AudioPlayer"
    private val codecThread = HandlerThread("audio-decoder", Thread.NORM_PRIORITY).apply { start() }
    private val handler = Handler(codecThread.looper)
    private val pending = ConcurrentLinkedQueue<ByteArray>()
    private val running = AtomicBoolean(false)
    private var codec: MediaCodec? = null
    private var track: AudioTrack? = null
    private var config: CodecConfig? = null

    fun configure(config: CodecConfig) {
        this.config = config
        startCodec()
        startTrack()
    }

    fun queueAAC(buffer: ByteBuffer, presentationTimeUs: Long) {
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        pending.offer(bytes)
    }

    fun stop() {
        running.set(false)
        try { codec?.stop(); codec?.release() } catch (_: Throwable) {}
        try { track?.stop(); track?.release() } catch (_: Throwable) {}
        codec = null
        track = null
        pending.clear()
    }

    fun release() {
        stop()
        codecThread.quitSafely()
    }

    private fun startCodec() {
        val cfg = config ?: return
        try {
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, cfg.audioSampleRate, cfg.audioChannels).apply {
                setInteger(MediaFormat.KEY_IS_ADTS, 1)
                setInteger(MediaFormat.KEY_AAC_PROFILE, 2)
            }
            val mc = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            mc.setCallback(callback, handler)
            mc.configure(format, null, null, 0)
            mc.start()
            codec = mc
            running.set(true)
        } catch (t: Throwable) {
            Log.e(tag, "audio codec start failed", t)
        }
    }

    private fun startTrack() {
        val cfg = config ?: return
        val channelMask = if (cfg.audioChannels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val minBuffer = AudioTrack.getMinBufferSize(cfg.audioSampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT)
        track = AudioTrack.Builder()
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(cfg.audioSampleRate)
                    .setChannelMask(channelMask)
                    .build()
            )
            .setBufferSizeInBytes(minBuffer * 4)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            if (!running.get()) return
            val data = pending.poll() ?: run {
                handler.postDelayed({
                    if (running.get()) {
                        runCatching { codec.queueInputBuffer(index, 0, 0, 0, 0) }
                    }
                }, 5)
                return
            }
            val buf = codec.getInputBuffer(index) ?: return
            buf.clear()
            buf.put(data)
            codec.queueInputBuffer(index, 0, data.size, System.nanoTime() / 1_000L, 0)
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            val buf = codec.getOutputBuffer(index)
            if (buf != null && info.size > 0) {
                val pcm = ByteArray(info.size)
                buf.position(info.offset)
                buf.limit(info.offset + info.size)
                buf.get(pcm)
                track?.write(pcm, 0, pcm.size, AudioTrack.WRITE_NON_BLOCKING)
            }
            try { codec.releaseOutputBuffer(index, false) } catch (_: Throwable) {}
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            Log.e(tag, "audio codec error", e)
        }
    }
}
