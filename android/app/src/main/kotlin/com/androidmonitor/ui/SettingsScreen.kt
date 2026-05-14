package com.androidmonitor.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.androidmonitor.R

data class StreamSettings(val scalePercent: Int = 100, val maxFps: Int = 60)

@Composable
fun SettingsScreen(
    settings: StreamSettings,
    onSettingsChange: (StreamSettings) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.padding(24.dp)) {
        Text(stringResource(R.string.settings_title))
        Spacer(modifier = Modifier.height(16.dp))
        Text("${stringResource(R.string.resolution_scale)}: ${settings.scalePercent}%")
        Slider(
            value = settings.scalePercent.toFloat(),
            onValueChange = { onSettingsChange(settings.copy(scalePercent = it.toInt())) },
            valueRange = 50f..100f,
            steps = 4
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text("${stringResource(R.string.max_fps)}: ${settings.maxFps}")
        Slider(
            value = settings.maxFps.toFloat(),
            onValueChange = { onSettingsChange(settings.copy(maxFps = it.toInt())) },
            valueRange = 30f..120f,
            steps = 8
        )
    }
}
