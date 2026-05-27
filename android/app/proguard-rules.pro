# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# PointyCastle / encrypt package — uses reflection extensively
-keep class org.bouncycastle.** { *; }
-keep class com.sun.crypto.** { *; }
-keepclassmembers class * implements java.security.Provider { *; }
-dontwarn org.bouncycastle.**

# Kotlin reflection
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Speech to text
-keep class com.csdcorp.speech_to_text.** { *; }

# Permission handler
-keep class com.baseflow.permissionhandler.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Image picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Share plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# pdfrx / pdfium native bridge
-keep class io.github.shigomany.pdfrx.** { *; }

# pdf / printing packages
-keep class com.example.printing.** { *; }

# MLKit text recognition — suppress missing optional language model classes
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# General rules to avoid stripping reflection-accessed classes
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
