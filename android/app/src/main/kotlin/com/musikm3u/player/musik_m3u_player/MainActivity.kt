package com.musikm3u.player.musik_m3u_player

import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CHANNEL = "com.musikm3u.player/media_store"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var pendingWidgetAction: String? = null

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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureWidgetAction(intent)
    }

    private fun captureWidgetAction(intent: Intent?) {
        val action = intent?.getStringExtra(MusikWidgetHelper.EXTRA_WIDGET_ACTION) ?: return
        intent.removeExtra(MusikWidgetHelper.EXTRA_WIDGET_ACTION)
        pendingWidgetAction = action
        methodChannel?.invokeMethod("onWidgetAction", action)
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
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
