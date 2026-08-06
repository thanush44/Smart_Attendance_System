# ProGuard rules for Google ML Kit and dependencies

# Keep ML Kit classes
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Keep Google Play Services internal ML Kit classes
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.android.gms.internal.mlkit_**

# Keep Google Android GMS classes used by ML Kit
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter Blue Plus & BLE Peripheral plugin rules
-keep class com.bosoco.flutter_blue_plus.** { *; }
-dontwarn com.bosoco.flutter_blue_plus.**
-keep class com.github.jasonross.flutter_ble_peripheral.** { *; }
-dontwarn com.github.jasonross.flutter_ble_peripheral.**
-keep class dev.flutter.plugins.** { *; }

