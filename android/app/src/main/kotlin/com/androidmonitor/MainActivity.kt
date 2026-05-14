package com.androidmonitor

import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.androidmonitor.codec.AudioPlayer
import com.androidmonitor.codec.VideoDecoder
import com.androidmonitor.connection.PacketWriter
import com.androidmonitor.input.KeyboardHandler
import com.androidmonitor.ui.MainScreen
import com.androidmonitor.ui.theme.AndroidMonitorTheme

class MainActivity : ComponentActivity() {
    private lateinit var keyboardHandler: KeyboardHandler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val manager = (application as App).connectionManager
        keyboardHandler = KeyboardHandler(PacketWriter(manager))

        val metrics = resources.displayMetrics
        val deviceFps = window.windowManager.defaultDisplay.refreshRate.toInt().coerceAtLeast(30)

        setContent {
            AndroidMonitorTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val videoDecoder = remember { VideoDecoder() }
                    val audioPlayer = remember { AudioPlayer() }
                    MainScreen(
                        manager = manager,
                        videoDecoder = videoDecoder,
                        audioPlayer = audioPlayer,
                        deviceWidth = metrics.widthPixels,
                        deviceHeight = metrics.heightPixels,
                        deviceFps = deviceFps
                    )
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (::keyboardHandler.isInitialized && keyboardHandler.handleHardwareKey(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
