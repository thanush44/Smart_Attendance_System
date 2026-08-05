import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // 10.0.2.2 is the special IP address pointing to localhost from the Android emulator.
  // For iOS emulator or web, use localhost. Update this to your deployed backend IP as needed.
  static const String baseUrl = 'http://10.0.2.2:8000'; 
  
  static String? token;
  static Map<String, dynamic>? currentUser;

  // Register user
  static Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String name,
    required String role,
    String? faceEmbedding,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'name': name,
        'role': role,
        'face_embedding': faceEmbedding,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(responseData['detail'] ?? 'Registration failed');
    }
    return responseData;
  }

  // Login user
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(responseData['detail'] ?? 'Login failed');
    }

    token = responseData['access_token'];
    currentUser = responseData['user'];
    return responseData;
  }

  // Fetch enrolled/taught classes
  static Future<List<dynamic>> getUserClasses(int userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId/classes'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load classes');
    }
    return jsonDecode(response.body);
  }

  // Enroll in a class (Student)
  static Future<void> enrollClass(int studentId, String classCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/classes/enroll'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'student_id': studentId,
        'class_code': classCode,
      }),
    );

    if (response.statusCode != 200) {
      final responseData = jsonDecode(response.body);
      throw Exception(responseData['detail'] ?? 'Enrollment failed');
    }
  }

  // Create a new class (Teacher)
  static Future<Map<String, dynamic>> createClass({
    required String name,
    required String code,
    required int teacherId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/classes/create'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'name': name,
        'code': code,
        'teacher_id': teacherId,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(responseData['detail'] ?? 'Class creation failed');
    }
    return responseData;
  }

  // Start attendance session (Teacher)
  static Future<Map<String, dynamic>> startSession(int classId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sessions/start'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'class_id': classId,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(responseData['detail'] ?? 'Failed to start session');
    }
    return responseData;
  }

  // Submit attendance check-in (Student)
  static Future<Map<String, dynamic>> submitAttendance({
    required int sessionId,
    required int studentId,
    required String otpToken,
    required bool verifiedProximity,
    required bool verifiedFace,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/submit'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'session_id': sessionId,
        'student_id': studentId,
        'otp_token': otpToken,
        'verified_proximity': verifiedProximity,
        'verified_face': verifiedFace,
      }),
    );

    final responseData = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(responseData['detail'] ?? 'Attendance submission failed');
    }
    return responseData;
  }
}
