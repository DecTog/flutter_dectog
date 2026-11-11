package app.adto.flutter_adto_adid

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The GAID for flutter_adto (`adto_adid` channel).
 *
 *  - getAdvertisingId -> { id, limited } | null (null without Play services)
 *  - trackingStatus / requestTracking -> "notSupported": Android has no
 *      prompt; the user's choice arrives as `limited` (and, on Android 12+,
 *      an all-zero id).
 *
 * AdvertisingIdClient blocks on a service bind, so the read runs off the
 * main thread.
 */
class AdtoAdIdPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "adto_adid").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAdvertisingId" -> readAdvertisingId(result)
            "trackingStatus", "requestTracking" -> result.success("notSupported")
            else -> result.notImplemented()
        }
    }

    private fun readAdvertisingId(result: MethodChannel.Result) {
        val context = appContext
        val pool = executor
        if (context == null || pool == null) return result.success(null)
        try {
            pool.execute {
                val value: Map<String, Any?>? = try {
                    val info = AdvertisingIdClient.getAdvertisingIdInfo(context)
                    mapOf("id" to info.id, "limited" to info.isLimitAdTrackingEnabled)
                } catch (_: Throwable) {
                    // No Play services, an old Play services, or the bind failed.
                    null
                }
                mainHandler.post {
                    try {
                        result.success(value)
                    } catch (_: Throwable) {
                        // The engine went away while the read was running.
                    }
                }
            }
        } catch (_: Exception) {
            // Executor shut down between the null check and execute().
            result.success(null)
        }
    }
}
