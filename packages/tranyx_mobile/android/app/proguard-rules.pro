##-------------------------------------------------------------------------------
## Flutter
##-------------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

##-------------------------------------------------------------------------------
## Firebase / Google Play Services
##-------------------------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

##-------------------------------------------------------------------------------
## Solana Mobile Client
##-------------------------------------------------------------------------------
-keep class com.solanamobile.** { *; }
-dontwarn com.solanamobile.**

##-------------------------------------------------------------------------------
## Kotlin / Coroutines
##-------------------------------------------------------------------------------
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

##-------------------------------------------------------------------------------
## OkHttp / Retrofit (used by many Firebase SDKs)
##-------------------------------------------------------------------------------
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

##-------------------------------------------------------------------------------
## Gson / JSON serialisation
##-------------------------------------------------------------------------------
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

##-------------------------------------------------------------------------------
## App-specific model classes (adjust package as needed)
##-------------------------------------------------------------------------------
-keep class com.terraph.tranyx.** { *; }

##-------------------------------------------------------------------------------
## Google Play Core (legacy task API referenced by Flutter's deferred components)
## These classes are not present in the feature-delivery artifact but are
## referenced by FlutterEngine. Suppress to prevent R8 failures.
##-------------------------------------------------------------------------------
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.**

##-------------------------------------------------------------------------------
## Multidex
##-------------------------------------------------------------------------------
-keep class androidx.multidex.** { *; }
