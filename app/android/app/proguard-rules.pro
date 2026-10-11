# ML Kit text recognition: the plugin references optional language models the app does not ship (only Latin is used).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
# flutter_webrtc
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
# flutter_local_notifications (Gson reflection on its stored notification models) and flutter_foreground_task
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**
