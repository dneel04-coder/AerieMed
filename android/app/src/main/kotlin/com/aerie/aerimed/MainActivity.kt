package com.aerie.aerimed

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Must be before super.onCreate() so Flutter inherits the inset handling.
        // Addresses the edge-to-edge enforcement required for Android 15 (API 35).
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
