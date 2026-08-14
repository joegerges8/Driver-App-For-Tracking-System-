package com.example.delivery_boy_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Must match _notificationChannelId in lib/services/background_location_service.dart.
        // Versioned: a channel's importance is locked in when it is created, so
        // the only way to change how the notification behaves on a phone that
        // already ran an older build is to leave the old channel behind and
        // make a new one.
        private const val LOCATION_CHANNEL_ID = "driver_location_channel_v4"

        // Channels earlier builds created. Deleted so they stop showing up as
        // leftover entries in the app's notification settings.
        private val OBSOLETE_CHANNEL_IDS = listOf(
            "driver_location_channel",
            "driver_location_channel_v2",
            "driver_location_channel_v3",
        )

        // Must match _channelName in lib/services/device_power_settings.dart.
        private const val POWER_CHANNEL = "delivery_boy_app/power"

        // The screens each vendor's power manager hides "let this app run in the
        // background" behind. There is no Android API for this — the setting is
        // the vendor's own, and the driver has to tap it themselves — so the most
        // the app can do is put them on the right screen.
        //
        // Several entries per vendor because the component moves between
        // firmware versions; they are tried in order and the first one that
        // resolves wins. Infinix, Tecno and itel are all Transsion (HiOS/XOS) and
        // share the same phone manager, which is why they share a list.
        private val AUTOSTART_COMPONENTS = mapOf(
            "transsion" to listOf(
                "com.cyin.himgr/com.cyin.himgr.autostart.AutoStartActivity",
                "com.transsion.phonemanager/com.itel.autobootmanager.activity.AutoBootMgrActivity",
                "com.transsion.phonemanager/.MainActivity",
            ),
            "xiaomi" to listOf(
                "com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity",
            ),
            "oppo" to listOf(
                "com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity",
                "com.coloros.safecenter/com.coloros.safecenter.startupapp.StartupAppListActivity",
                "com.oppo.safe/com.oppo.safe.permission.startup.StartupAppListActivity",
            ),
            "vivo" to listOf(
                "com.vivo.permissionmanager/com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.iqoo.secure/com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            ),
            "huawei" to listOf(
                "com.huawei.systemmanager/com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager/com.huawei.systemmanager.optimize.process.ProtectActivity",
            ),
        )

        // Fallback for vendors whose component names are unknown or have moved:
        // open the phone manager app itself and let the driver navigate. Keyed
        // the same way as AUTOSTART_COMPONENTS.
        private val MANAGER_PACKAGES = mapOf(
            "transsion" to listOf("com.transsion.phonemanager", "com.cyin.himgr"),
            "xiaomi" to listOf("com.miui.securitycenter"),
            "oppo" to listOf("com.coloros.safecenter", "com.oppo.safe"),
            "vivo" to listOf("com.iqoo.secure"),
            "huawei" to listOf("com.huawei.systemmanager"),
        )

        // Build.MANUFACTURER values grouped onto the keys above. Anything not
        // listed — Samsung included — gets the standard Android battery screen,
        // which is all those phones need.
        private fun vendorKeyFor(manufacturer: String): String? =
            when (manufacturer.lowercase()) {
                "infinix", "tecno", "itel", "transsion" -> "transsion"
                "xiaomi", "redmi", "poco" -> "xiaomi"
                "oppo", "realme", "oneplus" -> "oppo"
                "vivo", "iqoo" -> "vivo"
                "huawei", "honor" -> "huawei"
                else -> null
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                    "vendorKey" -> result.success(vendorKeyFor(Build.MANUFACTURER ?: ""))
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" ->
                        result.success(requestIgnoreBatteryOptimizations())
                    "openBatterySettings" -> result.success(openBatterySettings())
                    "openAutoStartSettings" -> result.success(openAutoStartSettings())
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
    }

    // Keeps the foreground service's notification out of the notification
    // shade entirely.
    //
    // Android will not run a location foreground service without one — that is
    // an OS rule with no flag to disable it, and the service is the only way to
    // report GPS while the app is off screen. What *can* be controlled is
    // whether the notice is ever displayed, and there are two levers, one per
    // Android generation:
    //
    //  - Android 13+ (TIRAMISU): foreground-service notices obey the
    //    POST_NOTIFICATIONS permission. The manifest removes that permission
    //    outright, so the notice never reaches the drawer while the service
    //    carries on running.
    //  - Android 8–12: no such permission exists, but a channel created at
    //    IMPORTANCE_NONE is a blocked channel, and nothing posted to it is
    //    shown.
    //
    // Together these cover every version this app supports (minSdk 24).
    //
    // What this cannot hide, on any version: the system's own "active apps" /
    // Task Manager list, reachable from the quick-settings shade on Android
    // 13+. Android deliberately gives the user an unremovable way to see what
    // is holding the CPU and the GPS, and no app can opt out of it.
    //
    // The cost is that the driver loses their only in-the-field signal that
    // tracking is alive — the notification used to carry the time of the last
    // fix. Detecting a stall now rests entirely on the failure streak the
    // service records and the banner AppMainScreen shows for it, which the
    // driver only sees once they open the app.
    //
    // Created here rather than left to the plugin because whichever call runs
    // first decides the channel's settings, and MainActivity.onCreate runs at
    // app launch, well before the service starts.
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return

        OBSOLETE_CHANNEL_IDS.forEach { manager.deleteNotificationChannel(it) }

        val channel = NotificationChannel(
            LOCATION_CHANNEL_ID,
            "Location sharing",
            NotificationManager.IMPORTANCE_NONE
        ).apply {
            description = "Required by Android while the app shares your location."
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
        }

        manager.createNotificationChannel(channel)
    }

    // ── Power management ────────────────────────────────────────────────────
    // Doze and the vendors' own "app freezer" layers are what stop a
    // backgrounded delivery from reporting its position. The battery-optimisation
    // exemption below is the part Android exposes to apps; everything past it is
    // a vendor screen the driver must tap through themselves.

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    // Asks Android for the exemption directly. Allowed here because continuous
    // background location *is* this app's core function — a delivery the
    // dispatcher cannot see is the product not working.
    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations()) return true

        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:$packageName"))

        // Some vendor builds ship without this dialog. Falling back to the
        // battery settings list means the driver still lands somewhere they can
        // fix it, instead of nothing happening when they tap.
        return startIfPossible(intent) || openBatterySettings()
    }

    private fun openBatterySettings(): Boolean =
        startIfPossible(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) ||
            openAppSettings()

    // Walks this vendor's known autostart screens and opens the first one that
    // exists, then the phone manager app, then — for Samsung and anything
    // unrecognised — the app's own settings page, which always resolves.
    private fun openAutoStartSettings(): Boolean {
        // Empty string for unrecognised vendors — it matches no key, so both
        // lookups fall through to the app's own settings page.
        val vendor = vendorKeyFor(Build.MANUFACTURER ?: "") ?: ""

        AUTOSTART_COMPONENTS[vendor].orEmpty().forEach { component ->
            val intent = Intent().setComponent(ComponentName.unflattenFromString(component))
            if (startIfPossible(intent)) return true
        }

        MANAGER_PACKAGES[vendor].orEmpty().forEach { pkg ->
            val intent = packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null && startIfPossible(intent)) return true
        }

        return openAppSettings()
    }

    private fun openAppSettings(): Boolean = startIfPossible(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))
    )

    // Vendor components come and go between firmware builds, and a component
    // that has been renamed throws rather than returning null. Every launch here
    // is best-effort by design: the caller falls through to the next candidate.
    private fun startIfPossible(intent: Intent): Boolean = try {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    } catch (e: Exception) {
        false
    }
}
