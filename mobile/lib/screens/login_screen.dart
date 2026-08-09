import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:convert';
import 'dart:math';
import '../services/api_service.dart';
import 'teacher_home.dart';
import 'student_flow.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLogin = true;
  bool _obscurePassword = true;
  String _username = '';
  String _password = '';
  String _name = '';
  String _role = 'student'; // 'student' or 'teacher'
  
  bool _isLoading = false;
  String? _errorMessage;

  // Face Registration Data
  bool _faceRegistered = false;
  String? _registeredEmbedding;

  // Camera fields for enrollment preview
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  FaceDetector? _faceDetector;

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        // Authenticate with server
        final result = await ApiService.login(
          username: _username,
          password: _password,
        );
        final role = result['user']['role'];
        if (mounted) {
          if (role == 'teacher') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const TeacherHomeScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StudentFlowScreen()),
            );
          }
        }
      } else {
        // Registration
        if (_role == 'student' && !_faceRegistered) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Please complete face enrollment first.";
          });
          return;
        }

        await ApiService.register(
          username: _username,
          password: _password,
          name: _name,
          role: _role,
          faceEmbedding: _role == 'student' ? _registeredEmbedding : null,
        );

        // Switch back to login page
        setState(() {
          _isLogin = true;
          _isLoading = false;
          _faceRegistered = false;
          _registeredEmbedding = null;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful! Please log in.')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll("Exception: ", "");
      });
    }
  }

  Future<void> _initCameraForEnrollment(StateSetter setDialogState) async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      setDialogState(() {
        _cameraInitialized = true;
      });
    } catch (e) {
      debugPrint("Error initializing camera for enrollment: $e");
    }
  }

  void _disposeCameraForEnrollment() {
    if (_cameraController != null) {
      _cameraController!.dispose();
      _cameraController = null;
    }
    _cameraInitialized = false;
    _faceDetector?.close();
    _faceDetector = null;
  }

  void _startFaceEnrollment() {
    bool scanning = false;
    String statusText = "Position your face inside the frame and look directly at the camera.";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!_cameraInitialized && _cameraController == null) {
              _initCameraForEnrollment(setDialogState);
            }
            
            void captureAndProcessFace() async {
              if (_cameraController == null || !_cameraInitialized) return;
              
              setDialogState(() {
                scanning = true;
                statusText = "Capturing image...";
              });
              
              try {
                final XFile imageFile = await _cameraController!.takePicture();
                
                setDialogState(() {
                  statusText = "Analyzing facial landmarks...";
                });
                
                final inputImage = InputImage.fromFilePath(imageFile.path);
                final List<Face> faces = await _faceDetector!.processImage(inputImage);
                
                if (faces.isEmpty) {
                  throw Exception("No face detected. Position your face in the oval and try again.");
                }
                
                final Face face = faces.first;
                
                final leftEye = face.landmarks[FaceLandmarkType.leftEye];
                final rightEye = face.landmarks[FaceLandmarkType.rightEye];
                final nose = face.landmarks[FaceLandmarkType.noseBase];
                
                if (leftEye == null || rightEye == null || nose == null) {
                  throw Exception("Facial landmarks not clear. Look directly at the camera in good lighting.");
                }
                
                final double dEyes = sqrt(pow(rightEye.position.x - leftEye.position.x, 2) + pow(rightEye.position.y - leftEye.position.y, 2));
                final double dLeftEyeNose = sqrt(pow(nose.position.x - leftEye.position.x, 2) + pow(nose.position.y - leftEye.position.y, 2));
                final double dRightEyeNose = sqrt(pow(nose.position.x - rightEye.position.x, 2) + pow(nose.position.y - rightEye.position.y, 2));
                
                if (dLeftEyeNose == 0.0 || dRightEyeNose == 0.0) {
                  throw Exception("Face alignment failed. Try again.");
                }
                
                final double r1 = dEyes / dLeftEyeNose;
                final double r2 = dEyes / dRightEyeNose;
                
                final Map<String, double> ratios = {'r1': r1, 'r2': r2};
                
                setState(() {
                  _faceRegistered = true;
                  _registeredEmbedding = jsonEncode(ratios);
                });
                
                _disposeCameraForEnrollment();
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Face template enrolled successfully!')),
                  );
                }
              } catch (e) {
                setDialogState(() {
                  scanning = false;
                  statusText = e.toString().replaceAll("Exception: ", "");
                });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1B29),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Enroll Face ID', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scanning ? const Color(0xFF34D399) : const Color(0xFFD4AF37),
                        width: 3
                      ),
                      color: Colors.black26,
                    ),
                    child: ClipOval(
                      child: (_cameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                          ? AspectRatio(
                              aspectRatio: 1.0,
                              child: CameraPreview(_cameraController!),
                            )
                          : const Center(
                              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  if (scanning)
                    const Text('Analyzing face...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            _disposeCameraForEnrollment();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: (_cameraInitialized && _cameraController != null && _cameraController!.value.isInitialized)
                              ? captureAndProcessFace
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: const Color(0xFF09070F),
                            minimumSize: const Size(120, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Capture', style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    )
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF09070F),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Official College Emblem Seal Header
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x1FD4AF37),
                        border: Border.all(
                          color: const Color(0x99D4AF37),
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40D4AF37),
                            blurRadius: 25,
                            spreadRadius: 3,
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/dsu_logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // College Title Header
                  const Text(
                    'DHANALAKSHMI SRINIVASAN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Text(
                    'UNIVERSITY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFD4AF37),
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    _isLogin ? 'Welcome Back' : 'Create Account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isLogin 
                      ? 'Log in to manage or submit attendance' 
                      : 'Enroll and register your biometrics',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 28),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Form Fields
                  if (!_isLogin) ...[
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFD4AF37)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                        ),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Enter your full name' : null,
                      onSaved: (val) => _name = val!.trim(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Username (or Student ID)',
                      prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFD4AF37)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                      ),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Enter username' : null,
                    onSaved: (val) => _username = val!.trim().toLowerCase(),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFD4AF37)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Enter password' : null,
                    onSaved: (val) => _password = val!,
                  ),
                  const SizedBox(height: 20),

                  // Role Selection
                  if (!_isLogin) ...[
                    const Text('I am registering as a:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _role = 'student'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _role == 'student' 
                                  ? const Color(0x26D4AF37) 
                                  : Colors.transparent,
                                border: Border.all(
                                  color: _role == 'student' ? const Color(0xFFD4AF37) : const Color(0xFF2E2A3A)
                                ),
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.school, size: 24, color: _role == 'student' ? const Color(0xFFD4AF37) : Colors.grey),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Student',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _role == 'student' ? const Color(0xFFD4AF37) : Colors.grey,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _role = 'teacher'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _role == 'teacher' 
                                  ? const Color(0x26D4AF37) 
                                  : Colors.transparent,
                                border: Border.all(
                                  color: _role == 'teacher' ? const Color(0xFFD4AF37) : const Color(0xFF2E2A3A)
                                ),
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.workspace_premium, size: 24, color: _role == 'teacher' ? const Color(0xFFD4AF37) : Colors.grey),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Teacher',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _role == 'teacher' ? const Color(0xFFD4AF37) : Colors.grey,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_role == 'student') ...[
                      InkWell(
                        onTap: _startFaceEnrollment,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _faceRegistered 
                              ? const Color(0xFF34D399).withValues(alpha: 0.1) 
                              : const Color(0x1FD4AF37),
                            border: Border.all(
                              color: _faceRegistered ? const Color(0xFF34D399) : const Color(0x99D4AF37),
                            ),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _faceRegistered ? Icons.check_circle : Icons.face,
                                color: _faceRegistered ? const Color(0xFF34D399) : const Color(0xFFD4AF37),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _faceRegistered ? 'Biometric Data Registered' : 'Enroll Biometric Face ID',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _faceRegistered ? const Color(0xFF34D399) : const Color(0xFFD4AF37),
                                        fontSize: 14
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _faceRegistered 
                                        ? 'Face template saved in secure storage' 
                                        : 'Required to pass liveness checks during attendance.',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    )
                                  ],
                                ),
                              ),
                              if (!_faceRegistered)
                                const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey)
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],

                  // Action Button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: const Color(0xFF09070F),
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                      elevation: 4,
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Color(0xFF09070F), strokeWidth: 2.5))
                      : Text(_isLogin ? 'Log In' : 'Sign Up'),
                  ),
                  const SizedBox(height: 16),

                  // Toggle Login/Register
                  TextButton(
                    onPressed: _isLoading 
                      ? null 
                      : () {
                          setState(() {
                            _isLogin = !_isLogin;
                            _errorMessage = null;
                          });
                        },
                    child: Text(
                      _isLogin ? 'Don\'t have an account? Sign Up' : 'Already have an account? Log In',
                      style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
