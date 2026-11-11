package app.adto.core

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Build

/**
 * Clipboard helpers for the LinkMe-style install path. The SDK only
 * READS the clipboard when the SDK asked for it: on Android 12+ every read shows
 * the system "pasted from your clipboard" notice, so [hasUrl] looks at the
 * clip DESCRIPTION only (mime types, sensitivity flag) and never at the
 * content. Every call runs on the platform thread (ClipboardManager needs a
 * Looper on older releases) and degrades to false / null on any failure.
 */
internal object Pasteboard {
    private const val MAX_URL_LENGTH = 2048
    private val SCHEME_RE = Regex("^[A-Za-z][A-Za-z0-9+.-]*$")

    private fun manager(context: Context): ClipboardManager? =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    /**
     * Best effort, description-only: the primary clip exists, is textual and
     * is not flagged sensitive (Android 13 EXTRA_IS_SENSITIVE — passwords
     * copied from a manager must never be read). Android cannot tell a URL
     * from other text without reading it, so "textual" is the signal.
     */
    fun hasUrl(context: Context): Boolean = try {
        val cm = manager(context)
        val desc = if (cm != null && cm.hasPrimaryClip()) cm.primaryClipDescription else null
        when {
            desc == null -> false
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                desc.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true -> false
            else -> desc.hasMimeType("text/*")
        }
    } catch (_: Throwable) {
        false
    }

    /**
     * The first clip item as a URL string (≤ 2048 chars, one token, a valid
     * scheme; http(s) needs a host, custom schemes need `://`), else null.
     * Android 10+ only serves the clipboard to the focused app, which the
     * first launch is.
     */
    fun readUrl(context: Context): String? = try {
        val cm = manager(context)
        val clip = cm?.primaryClip
        if (clip == null || clip.itemCount == 0) {
            null
        } else {
            val item = clip.getItemAt(0)
            val text = (item.text ?: item.uri?.toString() ?: item.coerceToText(context))
                ?.toString()?.trim().orEmpty()
            if (text.isEmpty() || text.length > MAX_URL_LENGTH || text.any { it.isWhitespace() }) {
                null
            } else {
                val uri = Uri.parse(text)
                val scheme = uri.scheme
                when {
                    scheme == null || !SCHEME_RE.matches(scheme) -> null
                    scheme.equals("http", true) || scheme.equals("https", true) ->
                        if (uri.host.isNullOrEmpty()) null else text
                    text.contains("://") -> text
                    else -> null
                }
            }
        }
    } catch (_: Throwable) {
        null
    }

    /**
     * A change marker for the primary clip — its description
     * timestamp (Android 8+), read without touching the content, so the SDK
     * clears only the clip it read. Null when there is no clip or the API
     * level has no timestamp.
     */
    fun changeMarker(context: Context): Long? = try {
        val cm = manager(context)
        val desc = if (cm != null && cm.hasPrimaryClip()) cm.primaryClipDescription else null
        // 0 means "not recorded": no marker, so nothing is ever cleared on it.
        if (desc != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) desc.timestamp.takeIf { it > 0 } else null
    } catch (_: Throwable) {
        null
    }

    /** Clear the primary clip after an AdTo link was credited (Branch clears too). */
    fun clear(context: Context): Boolean = try {
        val cm = manager(context)
        if (cm == null) {
            false
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                cm.clearPrimaryClip()
            } else {
                cm.setPrimaryClip(ClipData.newPlainText("", ""))
            }
            true
        }
    } catch (_: Throwable) {
        false
    }
}
