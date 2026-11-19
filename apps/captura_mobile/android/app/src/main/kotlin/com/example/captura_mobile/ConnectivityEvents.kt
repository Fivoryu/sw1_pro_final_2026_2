package com.example.captura_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** A validated Internet transition wakes the existing durable queue; no polling or new SDK. */
class ConnectivityEvents(context: Context) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        onCancel(null)
        callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                    main.post { if (callback === this) sink.success(true) }
                }
            }
        }.also { manager.registerNetworkCallback(NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), it) }
    }
    override fun onCancel(arguments: Any?) {
        callback?.let { manager.unregisterNetworkCallback(it) }
        callback = null
    }
}
