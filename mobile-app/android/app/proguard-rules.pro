# ProGuard rules for Al-Mudeer mobile app

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.embedding.android.** { *; }

# Flutter plugin registrant
-keep class com.royaraqamia.almudeer.MainActivity { *; }
-keep class com.royaraqamia.almudeer.TransferForegroundService { *; }

# Keep generated plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keep class com.google.firebase.analytics.connector.** { *; }
-keep class com.google.firebase.iid.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.installations.** { *; }

# Google Play Core
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-dontwarn com.google.android.play.core.**

# Agora SDK (Voice/Video calling)
-keep class io.agora.** { *; }
-keep class io.agora.rtc.** { *; }
-keep class io.agora.base.** { *; }
-dontwarn io.agora.**

# Gson serialization/deserialization
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Keep model classes with SerializedName
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep all public methods in data classes
-keepclassmembers class **.models.** {
    public *;
}

# Keep Kotlin metadata
-keepattributes RuntimeVisibleAnnotations
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Shared Preferences
-keep class android.content.SharedPreferences { *; }

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Path Provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }

# URL Launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Share Plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# Device Info Plus
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# Package Info Plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# Connectivity Plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Network Info Plus
-keep class dev.fluttercommunity.plus.network_info.** { *; }

# Sensors Plus
-keep class dev.fluttercommunity.plus.sensors.** { *; }

# Battery Plus
-keep class dev.fluttercommunity.plus.battery.** { *; }

# Android Alarm Manager
-keep class io.flutter.plugins.androidalarmmanager.** { *; }

# Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Work Manager
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Audio Service / Just Audio
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.just_audio.** { *; }

# Audio Session
-keep class com.ryanheise.audio_session.** { *; }

# ExoPlayer / Media3 - Prevent obfuscation that breaks player release
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# Keep ExoPlayer components for proper resource cleanup
-keepclassmembers class androidx.media3.exoplayer.ExoPlayerImpl { *; }
-keepclassmembers class androidx.media3.exoplayer.ExoPlayerImplInternal { *; }
-keepclassmembers class androidx.media3.decoder.** { *; }
-keepclassmembers class androidx.media3.datasource.** { *; }
-keepclassmembers class androidx.media3.extractor.** { *; }

# Keep codec classes
-keep class androidx.media3.codec.** { *; }

# Contacts Service
-keep class flutter.plugins.contactsservice.contactsservice.** { *; }

# Mobile Scanner (QR Code)
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Nearby Connections
-keep class com.pkmnapps.nearby_connections.** { *; }

# Emoji Picker
-keep class com.fintays.emoji_picker_flutter.** { *; }

# Shimmer
-keep class com.goder.progress_indicator.** { *; }

# Photo View
-keep class com.example.photo_view.** { *; }

# Chewie (Video Player)
-keep class io.flutter.plugins.videoplayer.** { *; }

# Cached Network Image
-keep class com.dylanvann.fastimage.** { *; }

# Flutter Slidable
-keep class com.letsar.slidable.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep setters in Views so that animations can still work
-keepclassmembers public class * extends android.view.View {
    void set*(***);
    *** get*();
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable implementations
-keep class * implements java.io.Serializable { *; }

# Keep enum values
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep custom exceptions
-keep public class * extends java.lang.Exception

# R8 full mode strips generic signatures, which is problematic for Retrofit and Gson
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# For using GSON @Expose annotation
-keepattributes AnnotationDefault
-keepattributes RuntimeVisibleAnnotations

# Don't strip annotations
-keepattributes *Annotation*

# Don't optimize methods that use reflection
-keepclassmembers class * {
    @retrofit2.http.* <methods>;
}

# OkHttp
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Retrofit
-keep class retrofit2.** { *; }
-dontwarn retrofit2.**

# Handle missing androidx.window classes (common in Flutter R8 builds)
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Keep R classes
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Keep Application class
-keep public class * extends android.app.Application

# Keep Service classes
-keep public class * extends android.app.Service

# Keep BroadcastReceiver classes
-keep public class * extends android.content.BroadcastReceiver

# Keep ContentProvider classes
-keep public class * extends android.content.ContentProvider

# Keep BackupAgent classes
-keep public class * extends android.app.backup.BackupAgent

# Suppress warnings for missing classes from Apache Tika
-dontwarn javax.xml.stream.XMLStreamException
-dontwarn javax.xml.stream.XMLStreamReader
-dontwarn javax.xml.stream.XMLInputFactory
-dontwarn javax.xml.stream.XMLEventReader
-dontwarn javax.xml.stream.XMLStreamWriter
-dontwarn javax.xml.stream.XMLOutputFactory
-dontwarn javax.xml.stream.events.XMLEvent
-dontwarn javax.xml.stream.events.StartElement
-dontwarn javax.xml.stream.events.EndElement
-dontwarn javax.xml.stream.events.Characters
-dontwarn javax.xml.namespace.QName
-dontwarn org.apache.tika.**
