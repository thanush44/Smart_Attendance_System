# Antigravity AI Agent Context & Full Project Specification
**Repository**: Smart Attendance Platform (`BunnyBadri/Smart_Attendance`)  
**Target Audience**: Antigravity AI Coding Assistant / Autonomous Agents  
**Version**: 3.0.0 (August 2026)  

---

## 🤖 Agent Autonomous Operating Principles

**CRITICAL INSTRUCTION**: Future AI agents working on this workspace MUST operate autonomously using the technical specifications documented herein. All system contracts, APIs, database schemas, and native Android rules are fully specified below. Do not ask the user for clarification on architectural patterns or API schemas.

---

## 📐 Full Architecture & Component Specifications

### 1. Database Schema (`backend/models.py` & `backend/database.py`)
- **`users`**: `id` (PK), `username` (VARCHAR unique), `name`, `hashed_password` (Bcrypt), `role` (`'student'`|`'teacher'`), `face_embedding` (JSON TEXT `{"r1": float, "r2": float}`).
- **`classes`**: `id` (PK), `name`, `code` (VARCHAR unique), `teacher_id` (FK $\rightarrow$ `users.id`).
- **`enrollments`**: `student_id` (FK $\rightarrow$ `users.id`), `class_id` (FK $\rightarrow$ `classes.id`).
- **`sessions`**: `id` (PK), `short_id` (VARCHAR 6-char PIN), `class_id` (FK $\rightarrow$ `classes.id`), `ble_uuid` (UUID4 string), `otp_secret` (Base32 TOTP secret), `is_active` (BOOL), `created_at` (DATETIME).
- **`attendance`**: `id` (PK), `session_id` (FK $\rightarrow$ `sessions.id`), `student_id` (FK $\rightarrow$ `users.id`), `verified_proximity` (BOOL), `verified_face` (BOOL), `status` (`'present'`), `timestamp` (DATETIME).

### 2. REST API & WebSocket Specs (`backend/main.py`)
- **`POST /auth/register`**: `{username, password, name, role, face_embedding}`
- **`POST /auth/login`**: `{username, password}` $\rightarrow$ Returns JWT Bearer token + user dict.
- **`GET /users/{user_id}/classes`**: Returns classes taught (teacher) or enrolled (student).
- **`POST /classes/create`**: `{name, code, teacher_id}`
- **`POST /classes/enroll`**: `{student_id, class_code}`
- **`POST /sessions/start`**: `{class_id}` $\rightarrow$ Creates session, generates `ble_uuid` and `otp_secret`.
- **`POST /attendance/submit`**: `{session_id, student_id, otp_token, verified_proximity, verified_face}`
  - TOTP validation: `pyotp.TOTP(session.otp_secret, interval=10)` with `valid_window=1` (10s interval, 1-step window = 10s drift tolerance).
- **`WS /ws/class/{session_id}`**: Pushes `otp_update` event every second (`token`, `expires_in`) and broadcasts `student_checkin` events.

### 3. Mobile Client Specifications (`mobile/lib`)
- **`student_flow.dart`**:
  - Step 0 (Face ID): ML Kit `FaceDetector`. Blink (`leftEyeOpenProbability < 0.2` & `rightEyeOpenProbability < 0.2`) + Smile (`smilingProbability > 0.8`). Ratio formula: $r_1 = d_{\text{eyes}}/d_{\text{leftEyeNose}}$, $r_2 = d_{\text{eyes}}/d_{\text{rightEyeNose}}$. Match threshold $\ge 80\%$.
  - Step 1 (QR Scan): `mobile_scanner` reads `{"session_id": int, "token": string}`.
  - Step 2 (BLE Scan): `flutter_blue_plus`. Timeout 8s, RSSI threshold $\ge -85\text{ dBm}$. Attribute matching checks `advName`, `localName`, `platformName`, and `serviceUuids` for `'SmartAtt'`.
  - Step 3 (Submit): POST to `/attendance/submit`.
- **`teacher_home.dart`**:
  - Starts session via API.
  - BLE Peripheral advertising (`flutter_ble_peripheral`): `serviceUuid` = `ble_uuid`, `localName` = `SmartAtt_[CODE]`, `includeDeviceName: true`.

---

## 📜 Strict Build & Native Android Rules

1. **ProGuard / R8 Release Build Rule**:
   - File: [`mobile/android/app/proguard-rules.pro`](file:///c:/Users/vmbad/Downloads/Smart_Attendance/mobile/android/app/proguard-rules.pro).
   - MUST preserve:
     - `com.google.mlkit.**`
     - `com.google.android.gms.internal.mlkit_**`
     - `com.google.android.gms.**`
     - `com.bosoco.flutter_blue_plus.**`
     - `com.github.jasonross.flutter_ble_peripheral.**`
     - `dev.flutter.plugins.**`
     - Native methods (`native <methods>;`)
   - [`mobile/android/app/build.gradle.kts`](file:///c:/Users/vmbad/Downloads/Smart_Attendance/mobile/android/app/build.gradle.kts) MUST reference `proguard-rules.pro` under `buildTypes.release`.

2. **Android Permission Rule**:
   - File: [`mobile/android/app/src/main/AndroidManifest.xml`](file:///c:/Users/vmbad/Downloads/Smart_Attendance/mobile/android/app/src/main/AndroidManifest.xml).
   - DO NOT add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN`. Removing this flag allows custom BLE beacon scanning at the OS level.

3. **Mandatory Verification Command**:
   - Always run release build verification after modifying code:
     ```bash
     cd mobile
     flutter build apk --release
     ```
