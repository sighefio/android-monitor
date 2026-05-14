package com.androidmonitor

import android.app.Application
import com.androidmonitor.connection.ConnectionManager

class App : Application() {
    val connectionManager: ConnectionManager by lazy { ConnectionManager() }

    override fun onTerminate() {
        super.onTerminate()
        connectionManager.shutdown()
    }
}
