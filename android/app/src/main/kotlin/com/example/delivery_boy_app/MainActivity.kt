package com.example.delivery_boy_app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        // Must match _notificationChannelId in lib/services/background_location_service.dart.
        // Versioned: a channel's importance is locked in when it is created, so
        // the only way to quieten the notification on a phone that already ran
        // the old build is to leave the old channel behind and make a new one.
        private const val LOCATION_CHANNEL_ID = "driver_location_channel_v2"

        // The channel the first release created, at the importance the
        // background-service plugin defaults to. Deleted so it stops showing up
        // as a leftover entry in the app's notification settings.
        private const val LEGACY_LOCATION_CHANNEL_ID = "driver_location_channel"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
        requestNotificationPermission()
    }

    // Android will not let a location foreground service run without a visible
    // notification, so the goal here is not to remove it — it cannot be removed
    // — but to strip it of everything that makes it intrusive. IMPORTANCE_MIN
    // is what keeps it out of the status bar and collapses it to a single quiet
    // line at the bottom of the shade; the rest silences the sound, vibration,
    // launcher badge and lock screen.
    //
    // Created here rather than left to the plugin because the plugin creates
    // the channel at IMPORTANCE_LOW, and whichever call runs first is the one
    // that decides. MainActivity.onCreate runs at app launch, well before the
    // driver taps Start Delivery.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return

        manager.deleteNotificationChannel(LEGACY_LOCATION_CHANNEL_ID)

        val channel = NotificationChannel(
            LOCATION_CHANNEL_ID,
            "Location sharing",
            NotificationManager.IMPORTANCE_MIN
        ).apply {
            description = "Required by Android while the app shares your location during a delivery."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
        }

        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    1001
                )
            }
        }
    }
}
