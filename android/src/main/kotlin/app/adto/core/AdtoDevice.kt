package app.adto.core

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telephony.TelephonyManager
import android.webkit.WebSettings
import java.util.concurrent.ExecutorService
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger

/**
 * The device reads behind every AdTo SDK's native layer, free of any
 * framework: the Flutter plugin and the React Native module both call these
 * and only translate the results. Shared as source: the
 * React Native repository copies this directory byte for byte.
 *
 * Every read returns null (or an empty result) on failure: enrichment must
 * never break install tracking. The UA, Meta and referrer reads block
 * (WebView load, cross-app provider IPC, service binds); callers run them
 * off the main thread.
 *
 *  - deviceId: Settings.Secure.ANDROID_ID. No GAID: it needs Google Play
 *    services and the AD_ID permission, which must not merge into every
 *    host app; the opt-in advertising-id packages read it.
 *  - carrierInfo: { mcc, mnc? } from TelephonyManager.networkOperator.
 *  - webViewUserAgent: WebSettings' default UA.
 *  - metaReferrer: Meta's on-device install referrer for the app's own
 *    Facebook App ID, { referrer, ts?, isCt? }; needs the <queries> entries.
 *  - installReferrers: every store's referrer, in parallel (InstallReferrers.kt).
 *  - noBackupDirectory: Context.noBackupFilesDir, where the SDK keeps its
 *    install sentinel so Auto Backup never restores a "tracked" marker.
 *  - packageInstallInfo: { firstInstallTime, lastUpdateTime, installer?,
 *    versionCode } (ms epochs) to validate the sentinel and tell an install
 *    from an update.
 *  - launchInfo: { referrer?, fromHistory, hasIntentData }: the
 *    FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY guard, so a relaunch from recents
 *    never re-logs the cold-start link.
 *  - domainVerification: App Links verification per declared host (12+).
 */
object AdtoDevice {
    const val DEFAULT_REFERRER_TIMEOUT_MS = 5000L
    const val MIN_REFERRER_TIMEOUT_MS = 500L
    const val MAX_REFERRER_TIMEOUT_MS = 60_000L

    private val META_REFERRER_AUTHORITIES = listOf(
        "com.facebook.katana.provider.InstallReferrerProvider",
        "com.instagram.contentprovider.InstallReferrerProvider",
        "com.facebook.lite.provider.InstallReferrerProvider",
    )
    private val META_REFERRER_PROJECTION = arrayOf("install_referrer", "is_ct", "actual_timestamp")

    fun deviceId(context: Context): String? = try {
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)?.takeIf { it.isNotEmpty() }
    } catch (_: Throwable) {
        null
    }

    fun carrierInfo(context: Context): Map<String, Any>? = try {
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        // networkOperator is MCC+MNC concatenated (3 + 2-3 digits).
        val operator = tm?.networkOperator ?: ""
        if (operator.length < 5 || operator.length > 6 || !operator.all { it.isDigit() }) {
            null
        } else {
            val mcc = operator.substring(0, 3)
            val mnc = operator.substring(3)
            if (mnc.isEmpty()) mapOf("mcc" to mcc) else mapOf("mcc" to mcc, "mnc" to mnc)
        }
    } catch (_: Throwable) {
        null
    }

    /** The device's real WebView User-Agent (Branch-parity signal). Blocks. */
    fun webViewUserAgent(context: Context): String? = try {
        WebSettings.getDefaultUserAgent(context)?.takeIf { it.isNotEmpty() }
    } catch (_: Throwable) {
        null
    }

    /**
     * Meta's on-device install referrer for the caller's own Facebook App
     * ID: the content providers the Facebook / Instagram / Facebook-Lite
     * apps expose, first non-empty wins. Authorities and columns follow
     * Meta's documentation: install_referrer, is_ct (1 = click-through,
     * 0 = view-through) and actual_timestamp (seconds, sent as ms). Blocks.
     */
    fun metaReferrer(context: Context, rawFbAppId: String?): Map<String, Any>? {
        val fbAppId = rawFbAppId?.trim() ?: ""
        if (fbAppId.isEmpty() || !fbAppId.all { it.isDigit() }) return null
        val resolver = context.contentResolver ?: return null
        for (authority in META_REFERRER_AUTHORITIES) {
            try {
                resolver.query(
                    Uri.parse("content://$authority/$fbAppId"),
                    META_REFERRER_PROJECTION, null, null, null,
                )?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use
                    val referrerIdx = cursor.getColumnIndex("install_referrer")
                    if (referrerIdx < 0) return@use
                    val referrer = cursor.getString(referrerIdx)?.trim() ?: ""
                    if (referrer.isEmpty()) return@use
                    val payload = mutableMapOf<String, Any>("referrer" to referrer)
                    val timeIdx = cursor.getColumnIndex("actual_timestamp")
                    if (timeIdx >= 0 && !cursor.isNull(timeIdx)) {
                        val tsSec = cursor.getLong(timeIdx)
                        if (tsSec > 0) payload["ts"] = tsSec * 1000L
                    }
                    val ctIdx = cursor.getColumnIndex("is_ct")
                    if (ctIdx >= 0 && !cursor.isNull(ctIdx)) {
                        payload["isCt"] = cursor.getInt(ctIdx) == 1
                    }
                    return payload
                }
            } catch (_: Exception) {
                // Provider absent, not exported, or rejected the query —
                // try the next app rather than giving up on all of them.
            }
        }
        return null
    }

    /**
     * Every requested store's install referrer, read in parallel on [pool]
     * and cut off at [timeoutMs] (default 5000, clamped 500–60000). Blocks
     * until then; never throws.
     */
    fun installReferrers(context: Context, pool: ExecutorService, timeoutMs: Long?, stores: List<String>?): Map<String, Any> {
        val timeout = (timeoutMs ?: DEFAULT_REFERRER_TIMEOUT_MS).coerceIn(MIN_REFERRER_TIMEOUT_MS, MAX_REFERRER_TIMEOUT_MS)
        val wanted = stores?.takeIf { it.isNotEmpty() } ?: ReferrerStores.ALL
        return try {
            InstallReferrerOrchestrator(context, pool).read(timeout, wanted)
        } catch (t: Throwable) {
            // The orchestrator itself never throws; this is belt and braces.
            wanted.associateWith { mapOf("status" to ReferrerStatus.ERROR, "error" to t.toString(), "attempts" to 0, "waitMs" to 0L) }
        }
    }

    fun noBackupDirectory(context: Context): String? = try {
        val dir = context.noBackupFilesDir
        if (!dir.exists()) dir.mkdirs()
        dir.absolutePath
    } catch (_: Throwable) {
        null
    }

    fun packageInstallInfo(context: Context): Map<String, Any>? = try {
        val pm = context.packageManager
        val packageName = context.packageName
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, 0)
        }
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(packageName)
            }
        } catch (_: Throwable) {
            null
        }
        val payload = mutableMapOf<String, Any>(
            "firstInstallTime" to info.firstInstallTime,
            "lastUpdateTime" to info.lastUpdateTime,
            "versionCode" to versionCode,
        )
        installer?.takeIf { it.isNotBlank() }?.let { payload["installer"] = it }
        payload
    } catch (_: Throwable) {
        null
    }

    /** Null without an activity. */
    fun launchInfo(activity: Activity?): Map<String, Any>? = try {
        val act = activity
        if (act == null) {
            null
        } else {
            val intent: Intent? = act.intent
            val referrer: Uri? = act.referrer
            val payload = mutableMapOf<String, Any>(
                "fromHistory" to ((intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0),
                "hasIntentData" to (intent?.data != null),
            )
            referrer?.toString()?.takeIf { it.isNotBlank() }?.let { payload["referrer"] = it }
            payload
        }
    } catch (_: Throwable) {
        null
    }

    /**
     * App Links verification per declared host (Android 12+), for
     * diagnostics(): "verified", "selected" (approved by the user), "none"
     * (not verified) or the raw state number. Null below Android 12 or on
     * any failure.
     */
    fun domainVerification(context: Context): Map<String, String>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            val manager = context.getSystemService(android.content.pm.verify.domain.DomainVerificationManager::class.java)
                ?: return null
            val state = manager.getDomainVerificationUserState(context.packageName) ?: return null
            state.hostToStateMap.mapValues { (_, v) ->
                when (v) {
                    android.content.pm.verify.domain.DomainVerificationUserState.DOMAIN_STATE_VERIFIED -> "verified"
                    android.content.pm.verify.domain.DomainVerificationUserState.DOMAIN_STATE_SELECTED -> "selected"
                    android.content.pm.verify.domain.DomainVerificationUserState.DOMAIN_STATE_NONE -> "none"
                    else -> v.toString()
                }
            }
        } catch (_: Throwable) {
            null
        }
    }

    /** Named daemon threads so a stuck store bind can never keep the process alive. */
    class DaemonThreadFactory : ThreadFactory {
        private val counter = AtomicInteger(0)
        override fun newThread(r: Runnable): Thread =
            Thread(r, "adto-io-${counter.incrementAndGet()}").apply { isDaemon = true }
    }
}
