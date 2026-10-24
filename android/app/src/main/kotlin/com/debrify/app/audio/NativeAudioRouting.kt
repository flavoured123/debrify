package com.debrify.app.audio

import android.content.Context
import android.os.Handler
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import com.debrify.app.diagnostics.DiagnosticFileLog

/** Shared by both native players. UI writes; Media3's playback thread reads. */
class NativeAudioRouting {
    @Volatile var requiresPcm: Boolean = false
        private set

    /**
     * "Audio passthrough" setting: send AC3 / E-AC3 (Atmos) / DTS to the HDMI
     * receiver even when the route doesn't advertise it (common behind ARC or
     * an AV receiver that Android reads as a TV).
     */
    @Volatile var forcePassthrough: Boolean = false

    /** "Decode all audio with FFmpeg": PCM out, for TV speakers that stay silent on bitstreams. */
    @Volatile var forceDecode: Boolean = false
    private var pendingRepreparePlayer: Player? = null

    fun update(nightMode: Boolean, systemEffects: Boolean, playbackSpeed: Float = 1f): Boolean {
        val next = nightMode || systemEffects || playbackSpeed != 1f || forceDecode
        val changed = next != requiresPcm
        requiresPcm = next
        return changed
    }

    fun setPlaybackSpeed(player: Player?, playbackSpeed: Float, routeChanged: Boolean) {
        if (routeChanged || (player != null && pendingRepreparePlayer === player)) {
            reprepare(player, playbackSpeed)
        } else {
            player?.setPlaybackSpeed(playbackSpeed)
        }
    }

    /**
     * Re-evaluate bypass/decoder selection, not just the effect's enabled flag.
     * stop/prepare retains the playlist, position, track overrides, speed and
     * playWhenReady. In particular, do not call play() on a paused session.
     * Set a requested speed AFTER stopping the old encoded sink, otherwise it
     * can reject the speed and report 1x back before PCM is configured.
     * An ended renderer can survive a seek, so defer BOTH its rebuild and speed
     * change until playback resumes. Otherwise ExoPlayer can see the requested
     * speed as already set and skip sending it again when the route is rebuilt.
     */
    fun reprepare(player: Player?, playbackSpeed: Float? = null): Boolean {
        pendingRepreparePlayer = null
        if (player == null) return false
        val hasMedia = player.mediaItemCount > 0
        val restart = hasMedia &&
            (player.playbackState == Player.STATE_READY ||
                player.playbackState == Player.STATE_BUFFERING)
        if (hasMedia && player.playbackState == Player.STATE_ENDED) {
            pendingRepreparePlayer = player
            return false
        }
        if (restart) player.stop()
        playbackSpeed?.let { player.setPlaybackSpeed(it) }
        if (restart) player.prepare()
        return restart
    }

    /** Called by both players before handling a playback-state change. */
    fun reprepareIfPending(player: Player?, playbackSpeed: Float): Boolean {
        if (pendingRepreparePlayer !== player) {
            // A replacement player already uses the current routing policy.
            pendingRepreparePlayer = null
            return false
        }
        if (player == null || (player.playbackState != Player.STATE_BUFFERING &&
                player.playbackState != Player.STATE_READY)) return false
        // reprepare clears the pending player BEFORE stop/prepare dispatch their
        // own state callbacks. Use the latest selection, even if it changed
        // again while ended or the old sink reset its reported speed to 1x.
        return reprepare(player, playbackSpeed)
    }
}

/** Native encoded output first; FFmpeg remains available for unsupported codecs. */
class NativeAudioRenderersFactory @JvmOverloads constructor(
    context: Context,
    private val routing: NativeAudioRouting,
    private val processors: Array<AudioProcessor> = emptyArray(),
) : DefaultRenderersFactory(context) {
    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        // Only change AUDIO ordering. In particular, preserve the caller's
        // video-extension preference and its IPTV video codec selector.
        val audioMode = when {
            extensionRendererMode == EXTENSION_RENDERER_MODE_OFF -> EXTENSION_RENDERER_MODE_OFF
            routing.forceDecode -> EXTENSION_RENDERER_MODE_PREFER   // FFmpeg first
            else -> EXTENSION_RENDERER_MODE_ON
        }
        super.buildAudioRenderers(context, audioMode, mediaCodecSelector,
            enableDecoderFallback, audioSink, eventHandler, eventListener, out)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean,
    ): AudioSink {
        // Force only when the route advertises no bitstream at all (some ARC
        // and AVR chains): a route that does report formats keeps its own
        // list, so TrueHD / DTS-HD it supports still go out untouched.
        val routeHasBitstream = try {
            @Suppress("DEPRECATION")
            val caps = AudioCapabilities.getCapabilities(context)
            caps.supportsEncoding(C.ENCODING_AC3) || caps.supportsEncoding(C.ENCODING_E_AC3) ||
                caps.supportsEncoding(C.ENCODING_DOLBY_TRUEHD) || caps.supportsEncoding(C.ENCODING_DTS)
        } catch (e: RuntimeException) {
            true
        }
        val builder = if (routing.forcePassthrough && !routing.forceDecode && !routeHasBitstream) {
            // Fixed capabilities are only honoured by a context-less builder:
            // the context one keeps re-reading what the route advertises.
            @Suppress("DEPRECATION")
            DefaultAudioSink.Builder().setAudioCapabilities(
                AudioCapabilities(
                    intArrayOf(
                        C.ENCODING_PCM_16BIT, C.ENCODING_AC3, C.ENCODING_E_AC3,
                        C.ENCODING_E_AC3_JOC, C.ENCODING_DTS, C.ENCODING_DTS_HD,
                        C.ENCODING_DOLBY_TRUEHD,
                    ),
                    8,
                ),
            )
        } else {
            DefaultAudioSink.Builder(context)
        }
        return EffectsAwareAudioSink(
            builder
                .setEnableFloatOutput(enableFloatOutput)
                .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                .setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(*processors))
                .build(),
            routing,
        )
    }
}

/** Effects and variable speed require decoded PCM instead of encoded bypass. */
internal class EffectsAwareAudioSink(
    delegate: AudioSink,
    private val routing: NativeAudioRouting,
) : ForwardingAudioSink(delegate) {
    private fun blocks(format: Format) =
        routing.requiresPcm && format.sampleMimeType != MimeTypes.AUDIO_RAW

    override fun supportsFormat(format: Format): Boolean =
        !blocks(format) && super.supportsFormat(format)

    override fun getFormatSupport(format: Format): Int =
        if (blocks(format)) AudioSink.SINK_FORMAT_UNSUPPORTED else super.getFormatSupport(format)

    override fun getFormatOffloadSupport(format: Format): AudioOffloadSupport =
        if (routing.requiresPcm) AudioOffloadSupport.DEFAULT_UNSUPPORTED
        else super.getFormatOffloadSupport(format)

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
        // Records the actual sink input, not merely a preference or source codec.
        val mode = if (inputFormat.sampleMimeType == MimeTypes.AUDIO_RAW) "pcm" else "encoded"
        val message = "mode=$mode mime=${inputFormat.sampleMimeType} " +
            "channels=${inputFormat.channelCount} rate=${inputFormat.sampleRate} " +
            "requiresPcm=${routing.requiresPcm}"
        Log.i("NativeAudio", message)
        DiagnosticFileLog.record("native_audio", "output_configured", message)
    }
}
