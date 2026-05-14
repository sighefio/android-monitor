package com.androidmonitor.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.androidmonitor.R
import com.androidmonitor.connection.ConnectionMode

@Composable
fun ConnectScreen(
    onConnect: (mode: ConnectionMode, host: String) -> Unit,
    modifier: Modifier = Modifier
) {
    var hostText by remember { mutableStateOf("") }
    Column(modifier = modifier.fillMaxSize().padding(24.dp)) {
        Text(text = stringResource(R.string.app_name))
        Spacer(modifier = Modifier.height(24.dp))
        OutlinedTextField(
            value = hostText,
            onValueChange = { hostText = it },
            label = { Text(stringResource(R.string.host_address)) }
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = { onConnect(ConnectionMode.WIFI, hostText) }, enabled = hostText.isNotBlank()) {
            Text(stringResource(R.string.connect_wifi))
        }
        Spacer(modifier = Modifier.height(8.dp))
        Button(onClick = { onConnect(ConnectionMode.USB, "127.0.0.1") }) {
            Text(stringResource(R.string.connect_usb))
        }
    }
}
