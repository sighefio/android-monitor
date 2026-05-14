package com.androidmonitor.codec

import android.media.MediaCodec
import android.media.MediaCodec.BufferInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

class VideoDecoder {
    private val tag = "VideoDecoder"
    private var codec: MediaCodec? = null
    private val codecThread = HandlerThread("video-decoder", Thread.MAX_PRIORITY).apply { start() }
    private val handler = Handler(codecThread.looper)
    private val pendingNALs = ConcurrentLinkedQueue<PendingFrame>()
    private val running = AtomicBoolean(false)
    private var surface: Surface? = null
    private var config: CodecConfig? = null

    private data class PendingFrame(val data: ByteArray, val ptsUs: Long, val isKeyframe: Boolean)

    fun configure(surface: Surface, config: CodecConfig) {
        this.surface = surface
        this.config = config
        startCodec()
    }

    fun updateSurface(newSurface: Surface) {
        if (config == null) return
        stop()
        surface = newSurface
        startCodec()
    }

    fun queueNAL(buffer: ByteBuffer, isKeyframe: Boolean, presentationTimeUs: Long) {
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)
        pendingNALs.offer(PendingFrame(bytes, presentationTimeUs, isKeyframe))
    }

    fun stop() {
        running.set(false)
        try {
            codec?.stop()
            codec?.release()
        } catch (t: Throwable) {
            Log.w(tag, "stop error: ${t.message}")
        }
        codec = null
        pendingNALs.clear()
    }

    fun release() {
        stop()
        codecThread.quitSafely()
    }

    private fun startCodec() {
        val cfg = config ?: return
        val surf = surface ?: return
        try {
            val mediaCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, cfg.width, cfg.height).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                }
                setInteger(MediaFormat.KEY_PRIORITY, 0)
                setInteger(MediaFormat.KEY_OPERATING_RATE, cfg.fps)
            }
            mediaCodec.setCallback(decoderCallback, handler)
            mediaCodec.configure(format, surf, null, 0)
            mediaCodec.start()
            codec = mediaCodec
            running.set(true)
            Log.i(tag, "decoder started ${cfg.width}x${cfg.height}@${cfg.fps}")
        } catch (t: Throwable) {
            Log.e(tag, "codec start failed", t)
        }
    }

    private val decoderCallback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            if (!running.get()) return
            val frame = pendingNALs.poll() ?: run {
                handler.postDelayed({
                    if (running.get()) {
                        runCatching { codec.queueInputBuffer(index, 0, 0, 0, 0) }
                    }
                }, 1)
                return
            }
            val buffer = codec.getInputBuffer(index) ?: return
            buffer.clear()
            buffer.put(frame.data)
            val flags = if (frame.isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            codec.queueInputBuffer(index, 0, frame.data.size, frame.ptsUs, flags)
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: BufferInfo) {
            try {
                codec.releaseOutputBuffer(index, info.size > 0)
            } catch (t: Throwable) {
                Log.w(tag, "releaseOutputBuffer error: ${t.message}")
            }
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            Log.i(tag, "output format changed: $format")
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            Log.e(tag, "codec error: ${e.message}", e)
        }
    }
}
