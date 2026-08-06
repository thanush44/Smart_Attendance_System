import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'dart:math';
import 'dart:convert';

class ApiService {
  static String? token; // Keeps compatibility with existing wrappers
  static Map<String, dynamic>? currentUser;

  // Helpers to get current Firebase user UID
  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  // Register user
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String name,
    required String role,
    String? faceEmbedding,
  }) async {
    // 1. Create User in Firebase Auth (Username is used as email.
    // For simplicity, if username is not an email format, we can append @smartattendance.com)
    final email = username.contains('@') ? username : '$username@smartattendance.com';
    
    UserCredential credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;

    final userData = {
      'id': uid,
      'username': username,
      'name': name,
      'role': role,
      'face_embedding': faceEmbedding,
      'created_at': FieldValue.serverTimestamp(),
    };

    // 2. Save user details to Firestore
    await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);

    return userData;
  }

  // Login user
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final email = username.contains('@') ? username : '$username@smartattendance.com';
    
    UserCredential credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;

    // Fetch user details from Firestore
    DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw Exception('User details not found in Firestore.');
    }

    final userData = doc.data() as Map<String, dynamic>;
    currentUser = userData;
    token = uid; // Set dummy token using Firebase UID to keep wrapper happy
    
    return {
      'access_token': uid,
      'user': userData
    };
  }

  // Fetch enrolled/taught classes
  static Future<List<dynamic>> getUserClasses(dynamic dummyId) async {
    final uid = currentUid;
    print("getUserClasses: currentUid=$uid, currentUser=$currentUser");
    if (uid == null || currentUser == null) return [];

    final role = currentUser!['role'];
    QuerySnapshot querySnapshot;

    if (role == 'teacher') {
      querySnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('teacher_id', isEqualTo: uid)
          .get();
    } else {
      querySnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('student_ids', arrayContains: uid)
          .get();
    }

    return querySnapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id; // Map document ID to 'id' field for compatibility
      return data;
    }).toList();
  }

  // Enroll in a class (Student)
  static Future<void> enrollClass(dynamic dummyId, String classCode) async {
    final uid = currentUid;
    if (uid == null) throw Exception('Not authenticated');

    // Find class by code
    final query = await FirebaseFirestore.instance
        .collection('classes')
        .where('code', isEqualTo: classCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Course code not found.');
    }

    final docId = query.docs.first.id;

    // Append student ID to enrollment array
    await FirebaseFirestore.instance.collection('classes').doc(docId).update({
      'student_ids': FieldValue.arrayUnion([uid])
    });
  }

  // Create a new class (Teacher)
  static Future<Map<String, dynamic>> createClass({
    required String name,
    required String code,
    required dynamic teacherId,
  }) async {
    final uid = currentUid;
    if (uid == null) throw Exception('Not authenticated');
    print("createClass: currentUid=$uid, creating code=$code");

    // Verify code uniqueness
    final dupCheck = await FirebaseFirestore.instance
        .collection('classes')
        .where('code', isEqualTo: code)
        .get();

    print("createClass dupCheck count: ${dupCheck.docs.length}");
    for (var doc in dupCheck.docs) {
      print("createClass: found duplicate doc: ${doc.id} => ${doc.data()}");
    }

    if (dupCheck.docs.isNotEmpty) {
      throw Exception('Course code already exists. (Matching Doc ID: ${dupCheck.docs.first.id})');
    }

    final newClass = {
      'name': name,
      'code': code,
      'teacher_id': uid,
      'student_ids': [],
      'created_at': FieldValue.serverTimestamp(),
    };

    final docRef = await FirebaseFirestore.instance.collection('classes').add(newClass);
    newClass['id'] = docRef.id;
    return newClass;
  }

  // Start attendance session (Teacher)
  static Future<Map<String, dynamic>> startSession(dynamic dummyClassId) async {
    final uid = currentUid;
    if (uid == null) throw Exception('Not authenticated');

    final String classId = dummyClassId.toString();

    // Fetch class details
    final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
    if (!classDoc.exists) throw Exception('Class not found');
    final classData = classDoc.data() as Map<String, dynamic>;

    // Close any previous active sessions for this class
    final activeSessions = await FirebaseFirestore.instance
        .collection('sessions')
        .where('class_id', isEqualTo: classId)
        .where('is_active', isEqualTo: true)
        .get();

    for (var doc in activeSessions.docs) {
      await doc.reference.update({'is_active': false});
    }

    // Generate random BLE UUID, base32 secret, and a short 6-digit session pin
    final bleUuid = _generateUuid();
    final otpSecret = _generateBase32Secret();
    final shortId = (100000 + Random().nextInt(900000)).toString(); // e.g. "491827"

    final sessionData = {
      'short_id': shortId,
      'class_id': classId,
      'class_name': classData['name'],
      'ble_uuid': bleUuid,
      'otp_secret': otpSecret,
      'is_active': true,
      'start_time': FieldValue.serverTimestamp(),
    };

    final docRef = await FirebaseFirestore.instance.collection('sessions').add(sessionData);
    
    return {
      'session_id': docRef.id, // String document ID
      'short_id': shortId,
      'class_id': classId,
      'class_name': classData['name'],
      'ble_uuid': bleUuid,
      'otp_secret': otpSecret,
      'is_active': true
    };
  }

  // Get active session for a specific class (if any exists)
  static Future<Map<String, dynamic>?> getActiveSession(String classId) async {
    final query = await FirebaseFirestore.instance
        .collection('sessions')
        .where('class_id', isEqualTo: classId)
        .where('is_active', isEqualTo: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final data = doc.data();
    return {
      'session_id': doc.id,
      'short_id': data['short_id'],
      'class_id': data['class_id'],
      'class_name': data['class_name'],
      'ble_uuid': data['ble_uuid'],
      'otp_secret': data['otp_secret'],
      'is_active': data['is_active'],
    };
  }

  // Submit attendance check-in (Student)
  static Future<Map<String, dynamic>> submitAttendance({
    required dynamic sessionId,
    required dynamic studentId,
    required String otpToken,
    required bool verifiedProximity,
    required bool verifiedFace,
  }) async {
    final uid = currentUid;
    if (uid == null || currentUser == null) throw Exception('Not authenticated');

    final String sessionDocId = sessionId.toString();

    // 1. Fetch Session from Firestore
    final doc = await FirebaseFirestore.instance.collection('sessions').doc(sessionDocId).get();
    if (!doc.exists) throw Exception('Attendance session not found.');
    final sessionData = doc.data() as Map<String, dynamic>;

    if (sessionData['is_active'] != true) {
      throw Exception('Attendance session is no longer active.');
    }

    // 2. Verify Student is Enrolled in Class
    final String classId = sessionData['class_id'];
    final classDoc = await FirebaseFirestore.instance.collection('classes').doc(classId).get();
    if (!classDoc.exists) throw Exception('Course details not found.');
    final classData = classDoc.data() as Map<String, dynamic>;
    final List<dynamic> enrolledStudents = classData['student_ids'] ?? [];

    if (!enrolledStudents.contains(uid)) {
      throw Exception('You are not enrolled in this course.');
    }

    // 3. Check for existing logs
    final doubleCheck = await FirebaseFirestore.instance
        .collection('attendance')
        .where('session_id', isEqualTo: sessionDocId)
        .where('student_id', isEqualTo: uid)
        .limit(1)
        .get();

    if (doubleCheck.docs.isNotEmpty) {
      return {'message': 'Attendance already marked', 'status': 'present'};
    }

    // 4. Validate TOTP locally using dart_otp (10s rolling)
    final otpSecret = sessionData['otp_secret'];
    final totp = TOTP(secret: otpSecret, interval: 10, digits: 6);
    
    // Validate. dart_otp verify method compares current timestamp
    bool isValid = totp.verify(otp: otpToken);
    
    // Fallback: Check previous time slot to allow 10s network latency drift
    if (!isValid) {
      isValid = totp.verify(otp: otpToken, time: DateTime.now().subtract(const Duration(seconds: 10)));
    }

    if (!isValid) {
      throw Exception('Invalid or expired QR code token.');
    }

    if (!verifiedProximity) {
      throw Exception('Proximity check failed. You must be in the classroom.');
    }

    if (!verifiedFace) {
      throw Exception('Face recognition check failed.');
    }

    // 5. Save attendance record
    final log = {
      'session_id': sessionDocId,
      'student_id': uid,
      'student_name': currentUser!['name'],
      'student_username': currentUser!['username'],
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'present',
      'verified_proximity': true,
      'verified_face': true,
    };

    await FirebaseFirestore.instance.collection('attendance').add(log);

    return {'message': 'Attendance marked successfully!', 'status': 'present'};
  }

  // Fetch session attendance list (Teacher)
  static Future<List<dynamic>> getSessionAttendance(dynamic sessionId) async {
    final String sessionDocId = sessionId.toString();
    final query = await FirebaseFirestore.instance
        .collection('attendance')
        .where('session_id', isEqualTo: sessionDocId)
        .get();

    return query.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      // Map Server Timestamps to string logic for compatibility
      if (data['timestamp'] is Timestamp) {
        data['timestamp'] = (data['timestamp'] as Timestamp).toDate().toIso8601String();
      }
      return data;
    }).toList();
  }

  // Close an active attendance session
  static Future<void> endSession(String sessionId) async {
    await FirebaseFirestore.instance.collection('sessions').doc(sessionId).update({
      'is_active': false,
      'end_time': FieldValue.serverTimestamp(),
    });
  }

  // --- CRYPTO HELPERS FOR OFFLINE MOCK SIGNALS ---

  static String _generateUuid() {
    final random = Random();
    final List<int> bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant 1
    final String hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _generateBase32Secret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final random = Random();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
