# Workspace Rules & Antigravity AI Guidelines

## 🤖 Smart Attendance Platform Development Rules & Architecture

1. **ProGuard / R8 Release Build Rule**:
   - Always preserve keep rules in `mobile/android/app/proguard-rules.pro` for ML Kit (`com.google.mlkit.**`, `com.google.android.gms.internal.mlkit_**`) and BLE plugins (`com.bosoco.flutter_blue_plus.**`, `com.github.jasonross.flutter_ble_peripheral.**`).
   - `mobile/android/app/build.gradle.kts` MUST reference `proguard-rules.pro` in `buildTypes.release`.

2. **Android Permission Rule**:
   - Do NOT add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN` in `mobile/android/app/src/main/AndroidManifest.xml`, as it blocks custom BLE beacon scanning at the OS level.

3. **BLE Scanning & Advertising Rules**:
   - In `mobile/lib/screens/student_flow.dart`, BLE scan matching must check `advName`, `localName`, `platformName`, and `serviceUuids`.
   - Use an 8-second scan timeout and `-85 dBm` RSSI threshold.
   - In `mobile/lib/screens/teacher_home.dart`, `AdvertiseData` must set `includeDeviceName: true`.

4. **Biometric Liveness & Ratio Matching**:
   - Facial ratio calculation ($r_1 = d_{\text{eyes}}/d_{\text{leftEyeNose}}, r_2 = d_{\text{eyes}}/d_{\text{rightEyeNose}}$) stored as JSON string in Firestore/SQLite (`face_embedding`).
   - Interactive liveness check requires blink (`eyeOpenProbability < 0.2`) and smile (`smilingProbability > 0.8`). Threshold is $\ge 80\%$.

5. **Verification Flow Sequence**:
   - Step 0: Face Liveness & Landmark Matching ($\ge 80\%$)
   - Step 1: Dynamic Rolling QR Code Scan
   - Step 2: Teacher BLE Proximity Verification ($\ge -85\text{ dBm}$)
   - Step 3: Server Check-in Submission (`POST /attendance/submit`)

6. **REST API & TOTP Specification**:
   - TOTP secret key generated as Base32 per session (`pyotp.random_base32()`).
   - TOTP refreshed every 10 seconds (`pyotp.TOTP(secret, interval=10)`). Token validation window is 1 step (`valid_window=1`).
