package app.dectog.flutter_dectog

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import app.dectog.core.DectogDevice
import app.dectog.core.Pasteboard
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The SDK's only authored platform channel (`dectog_device_identifiers`).
 * Every read lives in the framework-free `app.dectog.core` package
 * (DectogDevice, InstallReferrers, Pasteboard), shared as source with the
 * React Native SDK; this class only maps channel calls onto it:
 *
 *  - getDeviceId -> String | null (ANDROID_ID; the iOS-only `persist`
 *    argument is ignored — ANDROID_ID already survives reinstall for the
 *    same signing key)
 *  - getCarrierInfo -> { mcc, mnc? } | null
 *  - getWebViewUserAgent -> String | null
 *  - getMetaReferrer({ fbAppId }) -> { referrer, ts?, isCt? } | null
 *  - getInstallReferrers({ timeoutMs, stores? }) -> { store: entry }
 *  - getNoBackupDirectory -> String
 *  - getPackageInstallInfo -> { firstInstallTime, lastUpdateTime, installer?, versionCode }
 *  - getLaunchInfo -> { referrer?, fromHistory, hasIntentData } | null
 *  - pasteboardHasUrl / readPasteboardUrl / clearPasteboard / pasteboardChangeCount
 *  - getDomainVerification -> { host: state } | null
 *
 * The UA, Meta and referrer reads block, so they run on a cached background
 * pool and reply on the main thread. Every failure resolves null / false,
 * and unknown methods answer notImplemented.
 */
class DectogIdentifiersPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        executor = Executors.newCachedThreadPool(DectogDevice.DaemonThreadFactory())
        channel = MethodChannel(binding.binaryMessenger, "dectog_device_identifiers")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
        executor?.shutdownNow()
        executor = null
    }

    // ---- ActivityAware: only getLaunchInfo needs the activity ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext
        if (context == null) {
            result.success(null)
            return
        }
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "getDeviceId" -> result.success(DectogDevice.deviceId(context))
            "getCarrierInfo" -> result.success(DectogDevice.carrierInfo(context))
            "getWebViewUserAgent" -> runInBackground(result) { DectogDevice.webViewUserAgent(context) }
            "getMetaReferrer" -> runInBackground(result) { DectogDevice.metaReferrer(context, args?.get("fbAppId") as? String) }
            "getInstallReferrers" -> {
                val pool = executor ?: return result.success(emptyMap<String, Any>())
                val timeoutMs = (args?.get("timeoutMs") as? Number)?.toLong()
                val stores = (args?.get("stores") as? List<*>)?.filterIsInstance<String>()
                runInBackground(result, fallback = emptyMap<String, Any>()) {
                    DectogDevice.installReferrers(context, pool, timeoutMs, stores)
                }
            }
            "getNoBackupDirectory" -> result.success(DectogDevice.noBackupDirectory(context))
            "getPackageInstallInfo" -> result.success(DectogDevice.packageInstallInfo(context))
            "getLaunchInfo" -> result.success(DectogDevice.launchInfo(activity))
            "pasteboardHasUrl" -> result.success(Pasteboard.hasUrl(context))
            "readPasteboardUrl" -> result.success(Pasteboard.readUrl(context))
            "clearPasteboard" -> result.success(Pasteboard.clear(context))
            "pasteboardChangeCount" -> result.success(Pasteboard.changeMarker(context))
            "getDomainVerification" -> result.success(DectogDevice.domainVerification(context))
            else -> result.notImplemented()
        }
    }

    /**
     * Run a blocking read off the main thread and reply on it. Any
     * exception (or a detached engine) resolves [fallback].
     */
    private fun runInBackground(result: MethodChannel.Result, fallback: Any? = null, read: () -> Any?) {
        val pool = executor ?: return result.success(fallback)
        try {
            pool.execute {
                val value = try { read() } catch (_: Throwable) { fallback }
                mainHandler.post { replyQuietly(result, value) }
            }
        } catch (_: Exception) {
            // Executor shut down between the null check and execute().
            result.success(fallback)
        }
    }

    /** A reply after the engine detached throws; the value is lost either way. */
    private fun replyQuietly(result: MethodChannel.Result, value: Any?) {
        try {
            result.success(value)
        } catch (_: Throwable) {
        }
    }
}
