package com.debrify.app.tv

import android.content.Context

/** Device-specific IPTV workarounds kept outside the player activity so the
 * matching rules can be covered by plain JVM tests. */
internal object IptvDeviceQuirks {
    /**
     * The Google TV Streamer's MediaTek decoder can accept a progressive TS
     * stream joined on a non-IDR frame without ever rendering video, while
     * audio continues normally. The browse preview works because it uses the
     * stock (IDR-only) TS extractor. Start the fullscreen player on that same
     * strict path instead of waiting for the video-stall recovery ladder to
     * discover the quirk after visible freezes and re-tunes.
     *
     * Match the public model name and the firmware device codename. Either is
     * sufficient because OEM/region builds have not always exposed identical
     * display strings.
     */
    fun startsIptvWithStrictTs(
        manufacturer: String?,
        model: String?,
        device: String?,
    ): Boolean {
        val normalizedManufacturer = manufacturer.normalized()
        val normalizedModel = model.normalized()
        val normalizedDevice = device.normalized()

        return normalizedDevice == "kirkwood" ||
            (normalizedManufacturer == "google" &&
                normalizedModel.contains("google tv streamer"))
    }

    private fun String?.normalized(): String = orEmpty().trim().lowercase()

    // ── Learned strict demux ────────────────────────────────────────────
    // The player already discovers strict-decoder devices on its own: once
    // two different channels freeze (video stuck, audio running) under the
    // aggressive TS join flags, the rest of the session tunes strictly.
    // That discovery used to be forgotten on every app start, so boxes like
    // Fire TV and Amlogic/MediaTek Android TV units froze again on each
    // launch before the session re-learned it. Remember it per install.

    private const val PREFS = "debrify_iptv_device_quirks"
    private const val KEY_STRICT_TS = "strict_ts_learned"

    fun learnedStrictTs(context: Context): Boolean = try {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_STRICT_TS, false)
    } catch (_: Throwable) {
        false
    }

    fun rememberStrictTs(context: Context) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_STRICT_TS, true)
                .apply()
        } catch (_: Throwable) {
        }
    }

    /** Pure rule, unit-testable: the session has enough evidence that the
     *  DEVICE (not one odd channel) needs strict demux. */
    fun sessionProvesStrictDevice(strictChannelCount: Int): Boolean =
        strictChannelCount >= 2
}
