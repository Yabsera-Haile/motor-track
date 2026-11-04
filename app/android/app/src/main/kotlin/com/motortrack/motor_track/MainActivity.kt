package com.motortrack.motor_track

import com.motortrack.motor_track.reader.ReaderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reader: ReaderChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = ReaderChannel(this)
        reader = channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ReaderChannel.NAME).setMethodCallHandler(channel)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        reader?.onPermissionResult(requestCode)
    }
}
