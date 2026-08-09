package com.aerie.aerimed

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Must be before super.onCreate() so Flutter inherits the inset handling.
        // Addresses the edge-to-edge enforcement required for Android 15 (API 35).
        //
        // AndroidX's recommended androidx.activity.enableEdgeToEdge() can't be
        // called directly here: FlutterActivity extends plain Activity, not
        // ComponentActivity, which that extension function requires. This
        // replicates its actual effect by hand instead of just the
        // setDecorFitsSystemWindows piece — transparent system bars plus
        // disabling the automatic contrast scrim Android 15 otherwise draws
        // behind them, which setDecorFitsSystemWindows alone does not cover.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
        super.onCreate(savedInstanceState)
    }
}
