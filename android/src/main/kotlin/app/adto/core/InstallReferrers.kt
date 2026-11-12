package app.adto.core

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Install-referrer readers for every store the SDK knows, run in
 * parallel by [InstallReferrerOrchestrator] and reported to the SDK as one map
 * keyed by store:
 *
 *   { "<store>": { status, referrer?, clickTs?, installBeginTs?,
 *                  clickServerTs?, installBeginServerTs?, installVersion?,
 *                  instant?, attempts, waitMs, error? } }
 *
 * Stores: google_play | huawei | samsung | xiaomi | vivo. Only the stores
 * that were asked for appear; every entry carries `status`, `attempts` and
 * `waitMs`. Epochs are milliseconds. Status vocabulary (shared with the
 * server's install row):
 *
 *   ok                    a non-empty referrer was read
 *   organic               the store answered but recorded no referrer (blank,
 *                         or Play's "utm_source=google-play&utm_medium=organic")
 *   feature_not_supported the store app is too old for the API (terminal)
 *   permission_error      the store refused the read (terminal)
 *   developer_error       the store rejected the call after every retry
 *   service_unavailable   no connection after every retry — retry on a later
 *                         launch (Adjust re-reads every session)
 *   timeout               still running when the overall deadline passed
 *   not_available         the store / its library / its provider is absent
 *                         on this device (terminal)
 *   error                 anything else, with `error` text
 *
 * Mechanics follow the native SDKs: Play gets Adjust's policy (three
 * attempts three seconds apart, retrying only the transient response codes,
 * each attempt watchdog-bounded so a service that never calls back cannot
 * hang the read); Huawei and Vivo are plain ContentProvider / resolver
 * calls that need no SDK; Samsung and Xiaomi are reached by reflection so the
 * host app decides whether to ship those libraries.
 */
internal object ReferrerStores {
    const val GOOGLE_PLAY = "google_play"
    const val HUAWEI = "huawei"
    const val SAMSUNG = "samsung"
    const val XIAOMI = "xiaomi"
    const val VIVO = "vivo"
    val ALL = listOf(GOOGLE_PLAY, HUAWEI, SAMSUNG, XIAOMI, VIVO)
}

internal object ReferrerStatus {
    const val OK = "ok"
    const val ORGANIC = "organic"
    const val FEATURE_NOT_SUPPORTED = "feature_not_supported"
    const val SERVICE_UNAVAILABLE = "service_unavailable"
    const val DEVELOPER_ERROR = "developer_error"
    const val PERMISSION_ERROR = "permission_error"
    const val TIMEOUT = "timeout"
    const val ERROR = "error"
    const val NOT_AVAILABLE = "not_available"
}

/** Play's marker for an install with no campaign referrer (Branch rule). */
private const val PLAY_ORGANIC_REFERRER = "utm_source=google-play&utm_medium=organic"

/**
 * Seconds-or-milliseconds epoch to milliseconds. The Play API documents
 * seconds; the OEM providers are less consistent, so anything that already
 * looks like milliseconds (> 10^12, i.e. after 2001 in ms) passes through.
 * Zero / negative means "not recorded" and yields null.
 */
private fun toMs(value: Long?): Long? {
    if (value == null || value <= 0L) return null
    return if (value > 1_000_000_000_000L) value else value * 1000L
}

private fun Any?.asLong(): Long? = when (this) {
    null -> null
    is Number -> this.toLong()
    is String -> this.trim().toLongOrNull()
    else -> null
}

/** Build a referrer entry from the raw store fields (null-safe, omit-if-absent). */
private fun referrerEntry(
    referrer: String?,
    clickTs: Long?,
    installBeginTs: Long?,
    clickServerTs: Long? = null,
    installBeginServerTs: Long? = null,
    installVersion: String? = null,
    instant: Boolean? = null,
): MutableMap<String, Any> {
    val ref = referrer?.trim().orEmpty()
    val organic = ref.isEmpty() || ref == PLAY_ORGANIC_REFERRER
    val entry = mutableMapOf<String, Any>("status" to if (organic) ReferrerStatus.ORGANIC else ReferrerStatus.OK)
    if (ref.isNotEmpty()) entry["referrer"] = ref
    toMs(clickTs)?.let { entry["clickTs"] = it }
    toMs(installBeginTs)?.let { entry["installBeginTs"] = it }
    toMs(clickServerTs)?.let { entry["clickServerTs"] = it }
    toMs(installBeginServerTs)?.let { entry["installBeginServerTs"] = it }
    installVersion?.trim()?.takeIf { it.isNotEmpty() }?.let { entry["installVersion"] = it }
    instant?.let { entry["instant"] = it }
    return entry
}

private fun statusEntry(status: String, error: String? = null): MutableMap<String, Any> {
    val entry = mutableMapOf<String, Any>("status" to status)
    error?.takeIf { it.isNotBlank() }?.let { entry["error"] = it.take(256) }
    return entry
}

private fun describe(t: Throwable): String = "${t.javaClass.simpleName}: ${t.message ?: ""}".trim()

/** One store's reader. [read] runs on a pool thread and never throws. */
internal abstract class ReferrerReader(protected val context: Context) {
    abstract val store: String

    /** Connection attempts made so far (visible to the orchestrator on timeout). */
    val attempts = AtomicInteger(0)

    @Volatile
    var cancelled = false
        private set

    private val startedAt = SystemClock.elapsedRealtime()

    fun elapsedMs(): Long = SystemClock.elapsedRealtime() - startedAt

    /** Stop retrying; a reader blocked on a callback finishes at its watchdog. */
    fun cancel() {
        cancelled = true
    }

    fun read(): Map<String, Any> {
        val entry: MutableMap<String, Any> = try {
            doRead()
        } catch (e: InterruptedException) {
            statusEntry(ReferrerStatus.TIMEOUT, "interrupted")
        } catch (e: ClassNotFoundException) {
            statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(e))
        } catch (e: NoClassDefFoundError) {
            statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(e))
        } catch (t: Throwable) {
            statusEntry(ReferrerStatus.ERROR, describe(t))
        }
        entry["attempts"] = attempts.get()
        entry["waitMs"] = elapsedMs()
        return entry
    }

    protected abstract fun doRead(): MutableMap<String, Any>

    /** Sleep between attempts unless cancelled meanwhile (checked in 100 ms steps). */
    protected fun sleepUnlessCancelled(ms: Long) {
        val until = SystemClock.elapsedRealtime() + ms
        while (!cancelled && SystemClock.elapsedRealtime() < until) {
            Thread.sleep(minOf(100L, until - SystemClock.elapsedRealtime()).coerceAtLeast(1L))
        }
    }
}

/** Outcome of one Play / reflective connection attempt. */
private sealed class Attempt {
    class Done(val entry: MutableMap<String, Any>) : Attempt()
    class Retry(val code: Int?, val error: String) : Attempt()
}

/**
 * Google Play (com.android.installreferrer 2.2), Adjust's retry policy:
 * `MAX_INSTALL_REFERRER_RETRIES` + 1 attempts, `retryWaitTime` 3 s apart.
 * The client factory and the two delays are parameters only so the JVM tests
 * (src/test) can drive a fake client without waiting seconds.
 */
internal class PlayReferrerReader(
    context: Context,
    private val newClient: (Context) -> InstallReferrerClient = { InstallReferrerClient.newBuilder(it).build() },
    private val retryDelayMs: Long = RETRY_DELAY_MS,
    private val watchdogMs: Long = ATTEMPT_WATCHDOG_MS,
) : ReferrerReader(context) {
    override val store = ReferrerStores.GOOGLE_PLAY

    override fun doRead(): MutableMap<String, Any> {
        if (!isPackageInstalled(context, PLAY_STORE_PACKAGE)) {
            // No Play Store at all (Huawei/AOSP builds): binding would just burn
            // the retries. Package visibility for this lookup is declared in
            // the library manifest (<queries><package com.android.vending/>).
            return statusEntry(ReferrerStatus.NOT_AVAILABLE, "Play Store not installed")
        }
        var lastCode: Int? = null
        var lastError = ""
        for (attempt in 1..MAX_ATTEMPTS) {
            if (cancelled) break
            attempts.set(attempt)
            when (val outcome = attemptOnce()) {
                is Attempt.Done -> return outcome.entry
                is Attempt.Retry -> {
                    lastCode = outcome.code
                    lastError = outcome.error
                }
            }
            if (attempt < MAX_ATTEMPTS && !cancelled) sleepUnlessCancelled(retryDelayMs)
        }
        val status =
            if (lastCode == InstallReferrerResponse.DEVELOPER_ERROR) ReferrerStatus.DEVELOPER_ERROR
            else ReferrerStatus.SERVICE_UNAVAILABLE
        return statusEntry(status, lastError)
    }

    private fun attemptOnce(): Attempt {
        val client = try {
            newClient(context)
        } catch (t: Throwable) {
            return Attempt.Done(statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(t)))
        }
        val latch = CountDownLatch(1)
        val code = AtomicInteger(NO_CALLBACK)
        val disconnected = AtomicBoolean(false)
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    code.compareAndSet(NO_CALLBACK, responseCode)
                    latch.countDown()
                }

                override fun onInstallReferrerServiceDisconnected() {
                    disconnected.set(true)
                    latch.countDown()
                }
            })
        } catch (e: SecurityException) {
            // "Not allowed to bind to service" — a device policy, not transient.
            endQuietly(client)
            return Attempt.Done(statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(e)))
        } catch (t: Throwable) {
            endQuietly(client)
            return Attempt.Retry(null, describe(t))
        }
        try {
            // Watchdog: a bind that never calls back must not hang the read.
            val fired = latch.await(watchdogMs, TimeUnit.MILLISECONDS)
            if (!fired) return Attempt.Retry(null, "no callback within $watchdogMs ms")
            val c = code.get()
            if (c == NO_CALLBACK) {
                return Attempt.Retry(InstallReferrerResponse.SERVICE_DISCONNECTED, "service disconnected")
            }
            return when (c) {
                InstallReferrerResponse.OK -> {
                    val details = try {
                        client.installReferrer
                    } catch (t: Throwable) {
                        return Attempt.Retry(c, describe(t)) // RemoteException: connection dropped mid-read
                    }
                    Attempt.Done(
                        referrerEntry(
                            referrer = details.installReferrer,
                            clickTs = details.referrerClickTimestampSeconds,
                            installBeginTs = details.installBeginTimestampSeconds,
                            clickServerTs = details.referrerClickTimestampServerSeconds,
                            installBeginServerTs = details.installBeginTimestampServerSeconds,
                            installVersion = details.installVersion,
                            instant = details.googlePlayInstantParam,
                        ),
                    )
                }
                InstallReferrerResponse.FEATURE_NOT_SUPPORTED ->
                    Attempt.Done(statusEntry(ReferrerStatus.FEATURE_NOT_SUPPORTED))
                InstallReferrerResponse.PERMISSION_ERROR ->
                    Attempt.Done(statusEntry(ReferrerStatus.PERMISSION_ERROR))
                InstallReferrerResponse.SERVICE_UNAVAILABLE -> Attempt.Retry(c, "service unavailable")
                InstallReferrerResponse.SERVICE_DISCONNECTED -> Attempt.Retry(c, "service disconnected")
                InstallReferrerResponse.DEVELOPER_ERROR -> Attempt.Retry(c, "developer error")
                else -> Attempt.Retry(c, "unexpected response code $c")
            }
        } finally {
            endQuietly(client)
        }
    }

    private fun endQuietly(client: InstallReferrerClient) {
        try {
            client.endConnection()
        } catch (_: Throwable) {
        }
    }

    internal companion object {
        const val PLAY_STORE_PACKAGE = "com.android.vending"
        const val MAX_ATTEMPTS = 3 // Adjust: MAX_INSTALL_REFERRER_RETRIES (2) + the first try
        const val RETRY_DELAY_MS = 3000L // Adjust: retryWaitTime
        const val ATTEMPT_WATCHDOG_MS = 5000L
        const val NO_CALLBACK = Int.MIN_VALUE
    }
}

/**
 * Huawei AppGallery — the ContentProvider Adjust reads (HuaweiReferrerClient):
 * `content://com.huawei.appmarket.commondata/item/5` with the package name as
 * the selection argument; column 0 is the Huawei Ads referrer, 1/2 the click
 * and install timestamps, 4 the AppGallery track id. Which column carries a
 * store link's `referrer=` parameter is not documented consistently, so the
 * entry's `referrer` is whichever of the two contains `adto_click`, else the
 * ads referrer, else the track id; both raw values ride along as
 * `adsReferrer` / `trackId`. Needs the GET_COMMON_DATA permission and the
 * provider `<queries>` entry, both declared in this library's manifest.
 */
internal class HuaweiReferrerReader(context: Context) : ReferrerReader(context) {
    override val store = ReferrerStores.HUAWEI

    override fun doRead(): MutableMap<String, Any> {
        attempts.set(1)
        val cursor = try {
            context.contentResolver.query(
                Uri.parse("content://com.huawei.appmarket.commondata/item/5"),
                null, null, arrayOf(context.packageName), null,
            )
        } catch (e: SecurityException) {
            return statusEntry(ReferrerStatus.PERMISSION_ERROR, describe(e))
        } catch (t: Throwable) {
            return statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(t))
        } ?: return statusEntry(ReferrerStatus.NOT_AVAILABLE, "provider absent")
        cursor.use { c ->
            if (!c.moveToFirst()) return statusEntry(ReferrerStatus.ORGANIC)
            val adsReferrer = c.stringAt(0)
            val clickTs = c.stringAt(1).asLong()
            val installTs = c.stringAt(2).asLong()
            val trackId = c.stringAt(4)
            val referrer = listOfNotNull(trackId, adsReferrer).firstOrNull { it.contains("adto_click") }
                ?: adsReferrer ?: trackId
            val entry = referrerEntry(referrer, clickTs, installTs)
            adsReferrer?.let { entry["adsReferrer"] = it }
            trackId?.let { entry["trackId"] = it }
            return entry
        }
    }

    private fun android.database.Cursor.stringAt(index: Int): String? {
        if (index < 0 || index >= columnCount || isNull(index)) return null
        return try {
            getString(index)?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            null
        }
    }
}

/**
 * Vivo app store — `ContentResolver.call` on the referrer provider (Adjust
 * VivoReferrerClient): `read_referrer` answers a Bundle with
 * install_referrer, referrer_click_timestamp_seconds,
 * download_begin_timestamp_seconds and install_version.
 */
internal class VivoReferrerReader(context: Context) : ReferrerReader(context) {
    override val store = ReferrerStores.VIVO

    override fun doRead(): MutableMap<String, Any> {
        attempts.set(1)
        val bundle: Bundle = try {
            context.contentResolver.call(
                Uri.parse("content://com.vivo.appstore.provider.referrer"), "read_referrer", null, null,
            )
        } catch (e: SecurityException) {
            return statusEntry(ReferrerStatus.PERMISSION_ERROR, describe(e))
        } catch (t: Throwable) {
            return statusEntry(ReferrerStatus.NOT_AVAILABLE, describe(t))
        } ?: return statusEntry(ReferrerStatus.NOT_AVAILABLE, "provider absent")
        @Suppress("DEPRECATION")
        return referrerEntry(
            referrer = bundle.getString("install_referrer"),
            clickTs = bundle.get("referrer_click_timestamp_seconds").asLong(),
            installBeginTs = bundle.get("download_begin_timestamp_seconds").asLong(),
            installVersion = bundle.getString("install_version"),
        )
    }
}

/**
 * Shape of a Play-style client reached by reflection (Samsung Galaxy Store,
 * Xiaomi GetApps). The libraries are NOT compile dependencies: the host app
 * adds them when it ships through those stores, and the reader reports
 * `not_available` when the classes are missing (Branch's try/catch on
 * NoClassDefFoundError, done up front).
 */
internal class ReflectiveClientSpec(
    val store: String,
    val clientClass: String,
    val listenerClass: String,
    val responseClass: String,
    val setupFinishedMethod: String,
    val disconnectedMethod: String,
    val timeoutMs: Long,
)

internal val SAMSUNG_SPEC = ReflectiveClientSpec(
    store = ReferrerStores.SAMSUNG,
    clientClass = "com.sec.android.app.samsungapps.installreferrer.api.InstallReferrerClient",
    listenerClass = "com.sec.android.app.samsungapps.installreferrer.api.InstallReferrerStateListener",
    responseClass = "com.sec.android.app.samsungapps.installreferrer.api.InstallReferrerClient\$InstallReferrerResponse",
    setupFinishedMethod = "onInstallReferrerSetupFinished",
    disconnectedMethod = "onInstallReferrerServiceDisconnected",
    timeoutMs = 2000L, // Adjust: Samsung read capped at 2 s
)

internal val XIAOMI_SPEC = ReflectiveClientSpec(
    store = ReferrerStores.XIAOMI,
    clientClass = "com.miui.referrer.api.GetAppsReferrerClient",
    listenerClass = "com.miui.referrer.api.GetAppsReferrerStateListener",
    responseClass = "com.miui.referrer.annotation.GetAppsReferrerResponse",
    setupFinishedMethod = "onGetAppsReferrerSetupFinished",
    disconnectedMethod = "onGetAppsServiceDisconnected",
    timeoutMs = 3000L, // Adjust: Xiaomi read capped at 3 s
)

/**
 * One attempt against a Play-shaped client via reflection: newBuilder(context)
 * → build() → startConnection(listener proxy) → getInstallReferrer() →
 * endConnection(). Response codes mirror Play's (OK 0, SERVICE_DISCONNECTED
 * -1, SERVICE_UNAVAILABLE 1, FEATURE_NOT_SUPPORTED 2, DEVELOPER_ERROR 3);
 * the library's own constants are read when present.
 */
internal class ReflectiveReferrerReader(context: Context, private val spec: ReflectiveClientSpec) : ReferrerReader(context) {
    override val store = spec.store

    override fun doRead(): MutableMap<String, Any> {
        val clientCls = Class.forName(spec.clientClass) // ClassNotFoundException → not_available (read())
        val listenerCls = Class.forName(spec.listenerClass)
        val codes = responseCodes()
        attempts.set(1)

        val builder = newBuilder(clientCls)
        val client = builder.javaClass.getMethod("build").invoke(builder)
            ?: return statusEntry(ReferrerStatus.ERROR, "build() returned null")

        val latch = CountDownLatch(1)
        val code = AtomicInteger(NO_CALLBACK)
        val listener = Proxy.newProxyInstance(listenerCls.classLoader, arrayOf(listenerCls)) { proxy, method, args ->
            when (method.name) {
                spec.setupFinishedMethod -> {
                    code.compareAndSet(NO_CALLBACK, (args?.getOrNull(0) as? Int) ?: NO_CALLBACK)
                    latch.countDown()
                    null
                }
                spec.disconnectedMethod -> {
                    code.compareAndSet(NO_CALLBACK, codes.disconnected)
                    latch.countDown()
                    null
                }
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === args?.getOrNull(0)
                "toString" -> "AdtoReferrerListener(${spec.store})"
                else -> null
            }
        }
        try {
            clientCls.getMethod("startConnection", listenerCls).invoke(client, listener)
            if (!latch.await(spec.timeoutMs, TimeUnit.MILLISECONDS)) {
                return statusEntry(ReferrerStatus.TIMEOUT, "no callback within ${spec.timeoutMs} ms")
            }
            return when (val c = code.get()) {
                codes.ok -> {
                    val details = clientCls.getMethod("getInstallReferrer").invoke(client)
                        ?: return statusEntry(ReferrerStatus.ORGANIC)
                    referrerEntry(
                        referrer = details.getter("getInstallReferrer") as? String,
                        clickTs = details.getter("getReferrerClickTimestampSeconds").asLong(),
                        installBeginTs = details.getter("getInstallBeginTimestampSeconds").asLong(),
                        clickServerTs = details.getter("getReferrerClickTimestampServerSeconds").asLong(),
                        installBeginServerTs = details.getter("getInstallBeginTimestampServerSeconds").asLong(),
                        installVersion = details.getter("getInstallVersion") as? String,
                    )
                }
                codes.featureNotSupported -> statusEntry(ReferrerStatus.FEATURE_NOT_SUPPORTED)
                codes.developerError -> statusEntry(ReferrerStatus.DEVELOPER_ERROR)
                codes.serviceUnavailable, codes.disconnected -> statusEntry(ReferrerStatus.SERVICE_UNAVAILABLE)
                else -> statusEntry(ReferrerStatus.ERROR, "unexpected response code $c")
            }
        } finally {
            try {
                clientCls.getMethod("endConnection").invoke(client)
            } catch (_: Throwable) {
            }
        }
    }

    /** `Client.newBuilder(context)` — a Java static, or a Kotlin companion function. */
    private fun newBuilder(clientCls: Class<*>): Any {
        try {
            val m = clientCls.getMethod("newBuilder", Context::class.java)
            if (java.lang.reflect.Modifier.isStatic(m.modifiers)) return m.invoke(null, context)!!
        } catch (_: NoSuchMethodException) {
        }
        val companion = clientCls.getField("Companion").get(null)!!
        return companion.javaClass.getMethod("newBuilder", Context::class.java).invoke(companion, context)!!
    }

    private fun Any.getter(name: String): Any? = try {
        javaClass.getMethod(name).invoke(this)
    } catch (_: Throwable) {
        null
    }

    private class ResponseCodes(
        val ok: Int,
        val disconnected: Int,
        val serviceUnavailable: Int,
        val featureNotSupported: Int,
        val developerError: Int,
    )

    private fun responseCodes(): ResponseCodes {
        fun constant(name: String, default: Int): Int = try {
            Class.forName(spec.responseClass).getField(name).getInt(null)
        } catch (_: Throwable) {
            default
        }
        return ResponseCodes(
            ok = constant("OK", 0),
            disconnected = constant("SERVICE_DISCONNECTED", -1),
            serviceUnavailable = constant("SERVICE_UNAVAILABLE", 1),
            featureNotSupported = constant("FEATURE_NOT_SUPPORTED", 2),
            developerError = constant("DEVELOPER_ERROR", 3),
        )
    }

    private companion object {
        const val NO_CALLBACK = Int.MIN_VALUE
    }
}

/**
 * Runs the requested readers in parallel on the plugin's pool and collects
 * one entry per store, cutting the laggards off at the overall deadline with
 * a `timeout` entry (their attempts/waitMs so far). Never throws.
 */
internal class InstallReferrerOrchestrator(
    private val context: Context,
    private val pool: ExecutorService,
    /** The reader for a store name, null for an unknown one; a test seam. */
    private val readerFor: (String) -> ReferrerReader? = { defaultReader(context, it) },
) {
    fun read(timeoutMs: Long, stores: List<String>): Map<String, Any> {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        val readers = stores.distinct().mapNotNull(readerFor)
        val futures: List<Pair<ReferrerReader, Future<Map<String, Any>>>> = readers.map { reader ->
            reader to pool.submit<Map<String, Any>> { reader.read() }
        }
        val out = LinkedHashMap<String, Any>()
        for ((reader, future) in futures) {
            val remaining = (deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
            out[reader.store] = try {
                future.get(remaining, TimeUnit.MILLISECONDS)
            } catch (_: TimeoutException) {
                reader.cancel()
                future.cancel(true)
                mapOf(
                    "status" to ReferrerStatus.TIMEOUT,
                    "attempts" to reader.attempts.get(),
                    "waitMs" to reader.elapsedMs(),
                )
            } catch (t: Throwable) {
                mapOf(
                    "status" to ReferrerStatus.ERROR,
                    "error" to describe(t.cause ?: t),
                    "attempts" to reader.attempts.get(),
                    "waitMs" to reader.elapsedMs(),
                )
            }
        }
        return out
    }

    private companion object {
        fun defaultReader(context: Context, store: String): ReferrerReader? = when (store) {
            ReferrerStores.GOOGLE_PLAY -> PlayReferrerReader(context)
            ReferrerStores.HUAWEI -> HuaweiReferrerReader(context)
            ReferrerStores.VIVO -> VivoReferrerReader(context)
            ReferrerStores.SAMSUNG -> ReflectiveReferrerReader(context, SAMSUNG_SPEC)
            ReferrerStores.XIAOMI -> ReflectiveReferrerReader(context, XIAOMI_SPEC)
            else -> null // unknown store names are silently left out of the result
        }
    }
}

/** Whether a package is installed and visible (needs a `<queries>` entry on API 30+). */
internal fun isPackageInstalled(context: Context, packageName: String): Boolean = try {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        context.packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
    } else {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(packageName, 0)
    }
    true
} catch (_: PackageManager.NameNotFoundException) {
    false
} catch (_: Throwable) {
    true // an unexpected PM failure must not pre-empt the real connection attempt
}
