# ProGuard rules untuk M3U Musik Player (release build)

# Keep just_audio & Media3 / ExoPlayer classes
-keep class com.ryanheise.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# Flutter Play Core optional deferred-components references
-dontwarn com.google.android.play.core.**
