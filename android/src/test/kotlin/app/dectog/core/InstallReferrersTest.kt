package app.dectog.core

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Bundle
import android.os.RemoteException
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import com.android.installreferrer.api.ReferrerDetails
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The Play referrer reader and the orchestrator against a fake
 * InstallReferrerClient — the retry policy, the watchdog, the status
 * vocabulary the server stores, and the overall deadline. Run with
 * `./gradlew :flutter_dectog:testDebugUnitTest` from example/android.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class InstallReferrersTest {
    private lateinit var context: Context
    private val clients = mutableListOf<FakeClient>()

    /** One scripted answer per connection attempt. */
    private sealed class Answer {
        data class Code(val code: Int) : Answer()
        data class Referrer(val referrer: String, val clickTsSeconds: Long = 0, val installBeginTsSeconds: Long = 0) : Answer()
        object NoCallback : Answer()
        object Disconnect : Answer()
        object DropMidRead : Answer()
    }

    private class FakeClient(private val answer: Answer) : InstallReferrerClient() {
        var ended = false

        override fun isReady() = answer is Answer.Referrer

        override fun startConnection(listener: InstallReferrerStateListener) {
            when (answer) {
                is Answer.Code -> listener.onInstallReferrerSetupFinished(answer.code)
                is Answer.Referrer, Answer.DropMidRead -> listener.onInstallReferrerSetupFinished(InstallReferrerResponse.OK)
                Answer.Disconnect -> listener.onInstallReferrerServiceDisconnected()
                Answer.NoCallback -> Unit // a bind that never calls back
            }
        }

        override fun endConnection() {
            ended = true
        }

        override fun getInstallReferrer(): ReferrerDetails {
            if (answer is Answer.DropMidRead) throw RemoteException("connection dropped")
            val a = answer as Answer.Referrer
            return ReferrerDetails(
                Bundle().apply {
                    putString("install_referrer", a.referrer)
                    putLong("referrer_click_timestamp_seconds", a.clickTsSeconds)
                    putLong("install_begin_timestamp_seconds", a.installBeginTsSeconds)
                    putLong("referrer_click_timestamp_server_seconds", 0)
                    putLong("install_begin_timestamp_server_seconds", 0)
                    putString("install_version", "1.2.3")
                    putBoolean("google_play_instant", false)
                },
            )
        }
    }

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        installPlayStore()
    }

    @After
    fun everyClientWasEnded() {
        assertTrue("every connection is ended", clients.all { it.ended })
    }

    private fun installPlayStore() {
        shadowOf(context.packageManager).installPackage(PackageInfo().apply { packageName = "com.android.vending" })
    }

    private fun reader(vararg answers: Answer, watchdogMs: Long = 50): PlayReferrerReader {
        val queue = ArrayDeque(answers.toList())
        return PlayReferrerReader(
            context,
            newClient = { FakeClient(queue.removeFirst()).also(clients::add) },
            retryDelayMs = 0,
            watchdogMs = watchdogMs,
        )
    }

    @Test
    fun unavailableTwiceThenOk() {
        val entry = reader(
            Answer.Code(InstallReferrerResponse.SERVICE_UNAVAILABLE),
            Answer.Code(InstallReferrerResponse.SERVICE_UNAVAILABLE),
            Answer.Referrer("dtg_click=abc123&utm_source=x", clickTsSeconds = 1_700_000_000, installBeginTsSeconds = 1_700_000_100),
        ).read()
        assertEquals(ReferrerStatus.OK, entry["status"])
        assertEquals("dtg_click=abc123&utm_source=x", entry["referrer"])
        assertEquals(1_700_000_000_000L, entry["clickTs"])
        assertEquals(1_700_000_100_000L, entry["installBeginTs"])
        assertEquals("1.2.3", entry["installVersion"])
        assertEquals(3, entry["attempts"])
        assertEquals(3, clients.size)
    }

    @Test
    fun featureNotSupportedIsTerminal() {
        val entry = reader(Answer.Code(InstallReferrerResponse.FEATURE_NOT_SUPPORTED)).read()
        assertEquals(ReferrerStatus.FEATURE_NOT_SUPPORTED, entry["status"])
        assertEquals(1, entry["attempts"])
    }

    @Test
    fun permissionErrorIsTerminal() {
        val entry = reader(Answer.Code(InstallReferrerResponse.PERMISSION_ERROR)).read()
        assertEquals(ReferrerStatus.PERMISSION_ERROR, entry["status"])
        assertEquals(1, entry["attempts"])
    }

    @Test
    fun watchdogBoundsABindThatNeverCallsBack() {
        val started = System.nanoTime()
        val entry = reader(Answer.NoCallback, Answer.NoCallback, Answer.NoCallback, watchdogMs = 50).read()
        val tookMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        assertEquals(ReferrerStatus.SERVICE_UNAVAILABLE, entry["status"])
        assertEquals("no callback within 50 ms", entry["error"])
        assertEquals(3, entry["attempts"])
        assertTrue("three 50 ms watchdogs, not a hang (took $tookMs ms)", tookMs in 150..5_000)
    }

    @Test
    fun playOrganicMarkerIsOrganic() {
        val entry = reader(Answer.Referrer("utm_source=google-play&utm_medium=organic")).read()
        assertEquals(ReferrerStatus.ORGANIC, entry["status"])
        assertEquals(1, entry["attempts"])
    }

    @Test
    fun blankReferrerIsOrganicWithoutAReferrer() {
        val entry = reader(Answer.Referrer("  ")).read()
        assertEquals(ReferrerStatus.ORGANIC, entry["status"])
        assertFalse(entry.containsKey("referrer"))
        assertNull(entry["clickTs"])
    }

    @Test
    fun developerErrorAfterEveryRetry() {
        val entry = reader(
            Answer.Code(InstallReferrerResponse.DEVELOPER_ERROR),
            Answer.Code(InstallReferrerResponse.DEVELOPER_ERROR),
            Answer.Code(InstallReferrerResponse.DEVELOPER_ERROR),
        ).read()
        assertEquals(ReferrerStatus.DEVELOPER_ERROR, entry["status"])
        assertEquals(3, entry["attempts"])
    }

    @Test
    fun disconnectAndDroppedReadsAreRetried() {
        val entry = reader(Answer.Disconnect, Answer.DropMidRead, Answer.Referrer("dtg_click=zz")).read()
        assertEquals(ReferrerStatus.OK, entry["status"])
        assertEquals(3, entry["attempts"])
    }

    @Test
    fun noPlayStoreMeansNotAvailableWithoutBinding() {
        shadowOf(context.packageManager).deletePackage("com.android.vending")
        val entry = reader().read()
        assertEquals(ReferrerStatus.NOT_AVAILABLE, entry["status"])
        assertEquals(0, entry["attempts"])
        assertTrue(clients.isEmpty())
    }

    @Test
    fun orchestratorCutsOffALaggardAtTheDeadline() {
        val release = CountDownLatch(1)
        val slowAttempts = AtomicInteger(0)
        val pool = Executors.newCachedThreadPool()
        try {
            val orchestrator = InstallReferrerOrchestrator(context, pool) { store ->
                when (store) {
                    ReferrerStores.GOOGLE_PLAY -> reader(Answer.Referrer("dtg_click=fast"))
                    ReferrerStores.HUAWEI -> object : ReferrerReader(context) {
                        override val store = ReferrerStores.HUAWEI
                        override fun doRead(): MutableMap<String, Any> {
                            attempts.set(slowAttempts.incrementAndGet())
                            release.await(10, TimeUnit.SECONDS)
                            return mutableMapOf("status" to ReferrerStatus.OK)
                        }
                    }
                    else -> null
                }
            }
            val out = orchestrator.read(300, listOf(ReferrerStores.GOOGLE_PLAY, ReferrerStores.HUAWEI, "unknown_store", ReferrerStores.GOOGLE_PLAY))
            assertEquals(listOf(ReferrerStores.GOOGLE_PLAY, ReferrerStores.HUAWEI), out.keys.toList())
            assertEquals(ReferrerStatus.OK, (out[ReferrerStores.GOOGLE_PLAY] as Map<*, *>)["status"])
            val late = out[ReferrerStores.HUAWEI] as Map<*, *>
            assertEquals(ReferrerStatus.TIMEOUT, late["status"])
            assertEquals(1, late["attempts"])
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }
}
