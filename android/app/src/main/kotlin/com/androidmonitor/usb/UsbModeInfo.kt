package com.androidmonitor.usb

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.androidmonitor.R

@Composable
fun UsbModeInfo() {
    Column {
        Text("USB Mode")
        Spacer(modifier = Modifier.height(8.dp))
        Text(stringResource(R.string.usb_instructions))
    }
}
