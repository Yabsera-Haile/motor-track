package com.motortrack.motor_track

import android.content.Intent
import android.os.Bundle
import com.motortrack.motor_track.push.Notifications
import com.motortrack.motor_track.push.PushChannel
import com.motortrack.motor_track.reader.ReaderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reader: ReaderChannel? = null
    private val push = PushChannel()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val channel = ReaderChannel(this)
        reader = channel
        MethodChannel(messenger, ReaderChannel.NAME).setMethodCallHandler(channel)
        push.channel = MethodChannel(messenger, PushChannel.NAME).also { it.setMethodCallHandler(push) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.ensureChannel(this)
        push.handleIntent(this, intent)
    }

    // A notification tapped while the app is already open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        push.handleIntent(this, intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        reader?.onPermissionResult(requestCode)
    }
}
