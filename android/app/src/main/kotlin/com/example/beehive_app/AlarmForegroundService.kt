package com.example.beehive_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.session.MediaSession
import android.media.VolumeProvider
import android.os.Build
import android.os.IBinder

/**
 * Native alarm service. It is deliberately independent from Flutter/Dart so the
 * siren keeps working after the Flutter activity/process is closed.
 *
 * A hardware Volume Up or Volume Down press is intercepted by the active
 * MediaSession and stops the siren without dismissing the theft alert in
 * Supabase/Flutter.
 */
class AlarmForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.example.beehive_app.action.START_ALARM"
        const val ACTION_STOP = "com.example.beehive_app.action.STOP_ALARM"
        const val EXTRA_HIVE_NAME = "hive_name"
        const val EXTRA_HIVE_ID = "hive_id"

        private const val CHANNEL_ID = "theft_alarm"
        private const val NOTIFICATION_ID = 4701

        fun start(context: Context, hiveName: String?, hiveId: String?) {
            val intent = Intent(context, AlarmForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_HIVE_NAME, hiveName ?: "Κυψέλη")
                putExtra(EXTRA_HIVE_ID, hiveId ?: "")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AlarmForegroundService::class.java))
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var previousAlarmVolume = -1
    private var alarmVolumeWasChanged = false

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopAlarm()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val hiveName = intent?.getStringExtra(EXTRA_HIVE_NAME) ?: "Κυψέλη"
                startAlarm(hiveName)
            }
        }
        return START_NOT_STICKY
    }

    private fun startAlarm(hiveName: String) {
        // If an alarm is already running, do not create a second player/session.
        if (mediaPlayer?.isPlaying == true) return

        startForeground(NOTIFICATION_ID, buildNotification(hiveName))

        try {
            requestAlarmAudioFocus()
            forceAlarmStreamLoud()
            setupVolumeButtonKillSwitch()
            startSiren()
        } catch (e: Exception) {
            android.util.Log.e("BeehiveAlarm", "Failed to start siren", e)
            stopAlarm()
        }
    }

    private fun startSiren() {
        val player = MediaPlayer()
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )

        // Flutter assets are bundled inside the APK under flutter_assets/.
        // Copy the MP3 to cache first because compressed APK assets cannot always
        // be opened directly as a MediaPlayer file descriptor.
        val assetName = "flutter_assets/assets/audio/siren.mp3"
        val cachedFile = java.io.File(cacheDir, "beehive_siren.mp3")
        if (!cachedFile.exists() || cachedFile.length() == 0L) {
            assets.open(assetName).use { input ->
                cachedFile.outputStream().use { output -> input.copyTo(output) }
            }
        }

        player.setDataSource(cachedFile.absolutePath)
        player.isLooping = true
        player.prepare()
        player.setVolume(1.0f, 1.0f)
        player.start()
        mediaPlayer = player
    }

    private fun requestAlarmAudioFocus() {
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAcceptsDelayedFocusGain(false)
                .build()
            audioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                null,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            )
        }
    }

    private fun abandonAlarmAudioFocus() {
        val manager = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(null)
        }
    }

    private fun forceAlarmStreamLoud() {
        val manager = audioManager ?: return
        previousAlarmVolume = manager.getStreamVolume(AudioManager.STREAM_ALARM)
        val max = manager.getStreamMaxVolume(AudioManager.STREAM_ALARM)

        // The old Flutter implementation forced volume to ~95%. Native Android
        // does the same on the actual ALARM stream, then restores it when stopped.
        val target = kotlin.math.max(1, kotlin.math.round(max * 0.95f).toInt())
        if (previousAlarmVolume < target) {
            @Suppress("DEPRECATION")
            manager.setStreamVolume(AudioManager.STREAM_ALARM, target, 0)
            alarmVolumeWasChanged = true
        }
    }

    private fun restoreAlarmStreamVolume() {
        val manager = audioManager ?: return
        if (alarmVolumeWasChanged && previousAlarmVolume >= 0) {
            try {
                @Suppress("DEPRECATION")
                manager.setStreamVolume(AudioManager.STREAM_ALARM, previousAlarmVolume, 0)
            } catch (_: Exception) {
            }
        }
        previousAlarmVolume = -1
        alarmVolumeWasChanged = false
    }

    private fun setupVolumeButtonKillSwitch() {
        val session = MediaSession(this, "CleverScaleTheftAlarm")
        session.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
        )

        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() {
                // Nothing: the service controls playback.
            }

            override fun onPause() {
                stopAlarm()
            }

            override fun onStop() {
                stopAlarm()
            }
        })

        session.setPlaybackToRemote(object : VolumeProvider(
            VolumeProvider.VOLUME_CONTROL_ABSOLUTE,
            100,
            100
        ) {
            override fun onAdjustVolume(direction: Int) {
                // One Volume Up OR Volume Down press = silence only.
                stopAlarm()
            }

            override fun onSetVolumeTo(volume: Int) {
                // A hardware volume command that sets a level also silences.
                stopAlarm()
            }
        })

        session.setPlaybackState(
            android.media.session.PlaybackState.Builder()
                .setActions(
                    android.media.session.PlaybackState.ACTION_PLAY or
                        android.media.session.PlaybackState.ACTION_PAUSE or
                        android.media.session.PlaybackState.ACTION_STOP
                )
                .setState(
                    android.media.session.PlaybackState.STATE_PLAYING,
                    android.media.session.PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1.0f
                )
                .build()
        )
        session.isActive = true
        mediaSession = session
    }

    private fun releaseAlarmResources() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.reset()
                it.release()
            }
        } catch (_: Exception) {
        }
        mediaPlayer = null

        try {
            mediaSession?.isActive = false
            mediaSession?.release()
        } catch (_: Exception) {
        }
        mediaSession = null

        abandonAlarmAudioFocus()
        restoreAlarmStreamVolume()
    }

    private fun stopAlarm() {
        releaseAlarmResources()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Συναγερμός κλοπής",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Σειρήνα συναγερμού για παραβίαση κυψέλης"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(hiveName: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            4702,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, AlarmForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            4703,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("🚨 ΣΥΝΑΓΕΡΜΟΣ ΚΛΟΠΗΣ")
                .setContentText("Παραβίαση στην: $hiveName")
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_MAX)
                .setOngoing(true)
                .setAutoCancel(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setContentIntent(openPendingIntent)
                .addAction(
                    Notification.Action.Builder(
                        android.R.drawable.ic_media_pause,
                        "Σίγαση σειρήνας",
                        stopPendingIntent
                    ).build()
                )
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("🚨 ΣΥΝΑΓΕΡΜΟΣ ΚΛΟΠΗΣ")
                .setContentText("Παραβίαση στην: $hiveName")
                .setCategory(Notification.CATEGORY_ALARM)
                .setPriority(Notification.PRIORITY_MAX)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(openPendingIntent)
                .addAction(
                    android.R.drawable.ic_media_pause,
                    "Σίγαση σειρήνας",
                    stopPendingIntent
                )
                .build()
        }
    }

    override fun onDestroy() {
        // Do not call stopSelf() here; onDestroy is already the teardown path.
        releaseAlarmResources()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
