package com.musikm3u.player.musik_m3u_player

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.util.Rational
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CHANNEL = "com.musikm3u.player/media_store"
        @Suppress("unused")
        private val KEEP_NOTIF_ICON = R.drawable.ic_stat_music
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null
    private var castContext: CastContext? = null
    private var castListenerRegistered = false

    private val castSessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarting(session: CastSession) {}
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            notifyCastSession(true, session.castDevice?.friendlyName ?: "Chromecast / Nest")
        }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            notifyCastSession(false, null)
        }
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionEnded(session: CastSession, error: Int) {
            notifyCastSession(false, null)
        }
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            notifyCastSession(true, session.castDevice?.friendlyName ?: "Chromecast / Nest")
        }
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            notifyCastSession(false, null)
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {}
    }

    private fun notifyCastSession(connected: Boolean, deviceName: String?) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "onCastSessionChanged",
                mapOf("connected" to connected, "deviceName" to deviceName),
            )
        }
    }

    private fun ensureCastContext(): CastContext? {
        if (castContext != null) return castContext
        return try {
            val ctx = CastContext.getSharedInstance(this)
            if (!castListenerRegistered) {
                ctx.sessionManager.addSessionManagerListener(castSessionListener, CastSession::class.java)
                castListenerRegistered = true
            }
            castContext = ctx
            ctx
        } catch (_: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "queryAllAudio" -> {
                        executor.execute {
                            try {
                                val items = queryMediaStoreAudio()
                                mainHandler.post { result.success(items) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("MEDIA_STORE_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "getSupportedAbis" -> {
                        result.success(Build.SUPPORTED_ABIS.toList())
                    }
                    "consumePendingWidgetAction" -> {
                        val action = pendingWidgetAction
                        pendingWidgetAction = null
                        result.success(action)
                    }
                    "enterPictureInPicture" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .build()
                                result.success(enterPictureInPictureMode(params))
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "openCastDialog" -> {
                        val ctx = ensureCastContext()
                        if (ctx == null) {
                            try {
                                startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
                            } catch (_: Exception) {}
                            result.success(false)
                        } else {
                            try {
                                val themedCtx = ContextThemeWrapper(
                                    this,
                                    androidx.appcompat.R.style.Theme_AppCompat_DayNight_Dialog_Alert,
                                )
                                if (ctx.sessionManager.currentCastSession != null) {
                                    MediaRouteControllerDialog(themedCtx).show()
                                    result.success(true)
                                } else {
                                    val selector = ctx.mergedSelector
                                    if (selector != null) {
                                        val dialog = MediaRouteChooserDialog(themedCtx)
                                        dialog.routeSelector = selector
                                        dialog.show()
                                        result.success(true)
                                    } else {
                                        result.success(false)
                                    }
                                }
                            } catch (_: Exception) {
                                try {
                                    startActivity(Intent(Settings.ACTION_CAST_SETTINGS))
                                } catch (_: Exception) {}
                                result.success(false)
                            }
                        }
                    }
                    "castPlayMedia" -> {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title") ?: "M3U Musik"
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
                        val positionMs = (call.argument<Number>("positionMs")?.toLong()) ?: 0L
                        val session = ensureCastContext()?.sessionManager?.currentCastSession
                        val client = session?.remoteMediaClient
                        if (url == null || client == null) {
                            result.success(false)
                        } else {
                            val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
                                putString(MediaMetadata.KEY_TITLE, title)
                                if (subtitle.isNotEmpty()) {
                                    putString(MediaMetadata.KEY_ARTIST, subtitle)
                                }
                            }
                            val mediaInfo = MediaInfo.Builder(url)
                                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                                .setContentType(mimeType)
                                .setMetadata(metadata)
                                .build()
                            val loadReq = MediaLoadRequestData.Builder()
                                .setMediaInfo(mediaInfo)
                                .setAutoplay(true)
                                .setCurrentTime(positionMs)
                                .build()
                            client.load(loadReq)
                            result.success(true)
                        }
                    }
                    "castControl" -> {
                        val action = call.argument<String>("action")
                        val positionMs = (call.argument<Number>("positionMs")?.toLong()) ?: 0L
                        val client = ensureCastContext()?.sessionManager?.currentCastSession?.remoteMediaClient
                        if (client == null) {
                            result.success(false)
                        } else {
                            when (action) {
                                "play" -> client.play()
                                "pause" -> client.pause()
                                "stop" -> client.stop()
                                "seek" -> client.seek(positionMs)
                            }
                            result.success(true)
                        }
                    }
                    "disconnectCast" -> {
                        try {
                            ensureCastContext()?.sessionManager?.endCurrentSession(true)
                        } catch (_: Exception) {}
                        notifyCastSession(false, null)
                        result.success(true)
                    }
                    "updateHomeWidget" -> {
                        val title = call.argument<String>("title") ?: "M3U Musik"
                        val subtitle = call.argument<String>("subtitle") ?: "Siap Putar Offline"
                        val badge = call.argument<String>("badge") ?: "M3U MUSIK • OFFLINE"
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        val progress = call.argument<Int>("progress") ?: 0
                        val hasActiveSession = call.argument<Boolean>("hasActiveSession") ?: false
                        MusikWidgetHelper.saveStateAndRefresh(
                            context = applicationContext,
                            title = title,
                            subtitle = subtitle,
                            badge = badge,
                            isPlaying = isPlaying,
                            progressPercent = progress,
                            hasActiveSession = hasActiveSession,
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        captureWidgetAction(intent)
        mainHandler.post { ensureCastContext() }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        if (castListenerRegistered) {
            try {
                castContext?.sessionManager?.removeSessionManagerListener(
                    castSessionListener,
                    CastSession::class.java,
                )
            } catch (_: Exception) {}
        }
        executor.shutdown()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureWidgetAction(intent)
        mainHandler.post { ensureCastContext() }
    }

    private fun captureWidgetAction(intent: Intent?) {
        val action = intent?.getStringExtra(MusikWidgetHelper.EXTRA_WIDGET_ACTION) ?: return
        intent.removeExtra(MusikWidgetHelper.EXTRA_WIDGET_ACTION)
        pendingWidgetAction = action
        methodChannel?.invokeMethod("onWidgetAction", action)
    }

    private fun queryMediaStoreAudio(): List<Map<String, Any?>> {
        val list = ArrayList<Map<String, Any?>>()
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        @Suppress("DEPRECATION")
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.IS_RINGTONE,
            MediaStore.Audio.Media.IS_NOTIFICATION,
            MediaStore.Audio.Media.IS_ALARM,
            MediaStore.Audio.Media.IS_MUSIC,
        )

        val selection = "${MediaStore.Audio.Media.IS_RINGTONE} = 0 " +
            "AND ${MediaStore.Audio.Media.IS_NOTIFICATION} = 0 " +
            "AND ${MediaStore.Audio.Media.IS_ALARM} = 0"

        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        contentResolver.query(uri, projection, selection, null, sortOrder)?.use { cursor ->
            @Suppress("DEPRECATION")
            val dataIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            val titleIdx = cursor.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val albumIdx = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val durationIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DURATION)

            while (cursor.moveToNext()) {
                val path = if (dataIdx >= 0) cursor.getString(dataIdx) else null
                if (path.isNullOrBlank()) continue

                val lower = path.lowercase()
                if (lower.startsWith("/system/") ||
                    lower.startsWith("/product/") ||
                    lower.startsWith("/vendor/") ||
                    lower.contains("/ringtones/") ||
                    lower.contains("/notifications/") ||
                    lower.contains("/alarms/") ||
                    lower.contains("/android/data/") ||
                    lower.contains("/android/obb/")
                ) {
                    continue
                }

                val durationMs = if (durationIdx >= 0) cursor.getLong(durationIdx) else 0L
                if (durationMs in 1..2999) continue

                if (!File(path).exists()) continue

                val title = if (titleIdx >= 0) cursor.getString(titleIdx) else null
                val rawArtist = if (artistIdx >= 0) cursor.getString(artistIdx) else null
                val artist = if (rawArtist.isNullOrBlank() || rawArtist == "<unknown>") null else rawArtist
                val rawAlbum = if (albumIdx >= 0) cursor.getString(albumIdx) else null
                val album = if (rawAlbum.isNullOrBlank() || rawAlbum == "<unknown>") null else rawAlbum

                list.add(
                    mapOf(
                        "path" to path,
                        "title" to title,
                        "artist" to artist,
                        "album" to album,
                        "durationSec" to if (durationMs > 0) (durationMs / 1000).toInt() else null,
                    )
                )
            }
        }
        return list
    }
}
