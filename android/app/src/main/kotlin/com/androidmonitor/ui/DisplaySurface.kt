package com.androidmonitor.ui

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.androidmonitor.codec.CodecConfig
import com.androidmonitor.codec.VideoDecoder
import com.androidmonitor.input.TouchHandler

@Composable
fun DisplaySurface(
    decoder: VideoDecoder,
    touchHandler: TouchHandler,
    config: CodecConfig,
    modifier: Modifier = Modifier
) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            SurfaceView(context).apply {
                setOnTouchListener(touchHandler)
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        decoder.configure(holder.surface, config)
                    }
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                        decoder.updateSurface(holder.surface)
                    }
                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        decoder.stop()
                    }
                })
            }
        }
    )
    DisposableEffect(Unit) {
        onDispose { decoder.release() }
    }
}
