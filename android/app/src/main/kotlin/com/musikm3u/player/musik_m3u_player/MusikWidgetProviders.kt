package com.musikm3u.player.musik_m3u_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.KeyEvent
import android.widget.RemoteViews

object MusikWidgetHelper {
    const val PREFS_NAME = "musik_widget_prefs"
    const val KEY_TITLE = "title"
    const val KEY_SUBTITLE = "subtitle"
    const val KEY_BADGE = "badge"
    const val KEY_IS_PLAYING = "is_playing"
    const val KEY_PROGRESS = "progress"
    const val KEY_HAS_SESSION = "has_active_session"

    const val ACTION_PLAY_PAUSE = "com.musikm3u.player.WIDGET_PLAY_PAUSE"
    const val ACTION_NEXT = "com.musikm3u.player.WIDGET_NEXT"
    const val ACTION_PREV = "com.musikm3u.player.WIDGET_PREV"
    const val EXTRA_WIDGET_ACTION = "widget_action"

    fun saveStateAndRefresh(
        context: Context,
        title: String,
        subtitle: String,
        badge: String,
        isPlaying: Boolean,
        progressPercent: Int,
        hasActiveSession: Boolean = false,
    ) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TITLE, title)
            .putString(KEY_SUBTITLE, subtitle)
            .putString(KEY_BADGE, badge)
            .putBoolean(KEY_IS_PLAYING, isPlaying)
            .putInt(KEY_PROGRESS, progressPercent.coerceIn(0, 100))
            .putBoolean(KEY_HAS_SESSION, hasActiveSession)
            .apply()
        updateAllWidgets(context)
    }

    fun updateAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val compactIds = manager.getAppWidgetIds(
            ComponentName(context, MusikWidgetCompactProvider::class.java)
        )
        if (compactIds.isNotEmpty()) {
            updateWidgetsForLayout(context, manager, compactIds, R.layout.widget_musik_compact, hasPrev = false, hasFullMeta = false)
        }
        val barIds = manager.getAppWidgetIds(
            ComponentName(context, MusikWidgetBarProvider::class.java)
        )
        if (barIds.isNotEmpty()) {
            updateWidgetsForLayout(context, manager, barIds, R.layout.widget_musik_bar, hasPrev = true, hasFullMeta = false)
        }
        val fullIds = manager.getAppWidgetIds(
            ComponentName(context, MusikWidgetFullProvider::class.java)
        )
        if (fullIds.isNotEmpty()) {
            updateWidgetsForLayout(context, manager, fullIds, R.layout.widget_musik_full, hasPrev = true, hasFullMeta = true)
        }
    }

    fun updateWidgetsForLayout(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
        layoutId: Int,
        hasPrev: Boolean,
        hasFullMeta: Boolean,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val title = prefs.getString(KEY_TITLE, "M3U Musik") ?: "M3U Musik"
        val subtitle = prefs.getString(KEY_SUBTITLE, "Siap Putar Offline") ?: "Siap Putar Offline"
        val badge = prefs.getString(KEY_BADGE, "M3U MUSIK • OFFLINE") ?: "M3U MUSIK • OFFLINE"
        val isPlaying = prefs.getBoolean(KEY_IS_PLAYING, false)
        val progress = prefs.getInt(KEY_PROGRESS, 0)

        val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openAppPending = PendingIntent.getActivity(context, 10, launchIntent, immutableFlag)

        val playPausePending = PendingIntent.getBroadcast(
            context,
            11,
            Intent(context, WidgetActionReceiver::class.java).setAction(ACTION_PLAY_PAUSE),
            immutableFlag,
        )
        val nextPending = PendingIntent.getBroadcast(
            context,
            12,
            Intent(context, WidgetActionReceiver::class.java).setAction(ACTION_NEXT),
            immutableFlag,
        )
        val prevPending = PendingIntent.getBroadcast(
            context,
            13,
            Intent(context, WidgetActionReceiver::class.java).setAction(ACTION_PREV),
            immutableFlag,
        )

        val playIconRes = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }

        for (widgetId in widgetIds) {
            val views = RemoteViews(context.packageName, layoutId)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)
            views.setImageViewResource(R.id.btn_play_pause, playIconRes)

            views.setOnClickPendingIntent(R.id.widget_root, openAppPending)
            views.setOnClickPendingIntent(R.id.btn_play_pause, playPausePending)
            views.setOnClickPendingIntent(R.id.btn_next, nextPending)

            if (hasPrev) {
                views.setOnClickPendingIntent(R.id.btn_prev, prevPending)
            }
            if (hasFullMeta) {
                views.setTextViewText(R.id.widget_badge, badge)
                views.setProgressBar(R.id.widget_progress, 100, progress, false)
            }

            manager.updateAppWidget(widgetId, views)
        }
    }
}

class MusikWidgetCompactProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        MusikWidgetHelper.updateWidgetsForLayout(
            context, appWidgetManager, appWidgetIds,
            R.layout.widget_musik_compact, hasPrev = false, hasFullMeta = false
        )
    }
}

class MusikWidgetBarProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        MusikWidgetHelper.updateWidgetsForLayout(
            context, appWidgetManager, appWidgetIds,
            R.layout.widget_musik_bar, hasPrev = true, hasFullMeta = false
        )
    }
}

class MusikWidgetFullProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        MusikWidgetHelper.updateWidgetsForLayout(
            context, appWidgetManager, appWidgetIds,
            R.layout.widget_musik_full, hasPrev = true, hasFullMeta = true
        )
    }
}

class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val keyCode = when (action) {
            MusikWidgetHelper.ACTION_PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            MusikWidgetHelper.ACTION_NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            MusikWidgetHelper.ACTION_PREV -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> return
        }

        val prefs = context.getSharedPreferences(MusikWidgetHelper.PREFS_NAME, Context.MODE_PRIVATE)
        val hasActiveSession = prefs.getBoolean(MusikWidgetHelper.KEY_HAS_SESSION, false)

        if (!hasActiveSession && action == MusikWidgetHelper.ACTION_PLAY_PAUSE) {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MusikWidgetHelper.EXTRA_WIDGET_ACTION, action)
            }
            context.startActivity(launchIntent)
            return
        }

        // Route explicitly to our own AudioService MediaButtonReceiver so we never hijack other apps.
        val receiverComponent = ComponentName(
            context.packageName,
            "com.ryanheise.audioservice.MediaButtonReceiver",
        )
        val now = SystemClock.uptimeMillis()
        for (eventAction in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            val mediaIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = receiverComponent
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(now, now, eventAction, keyCode, 0))
            }
            context.sendBroadcast(mediaIntent)
        }
    }
}
