import 'package:flutter/material.dart';
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
  String _username = '';
  String _password = '';
  String _name = '';
  String _role = 'student'; // 'student' or 'teacher'
  
  bool _isLoading = false;
  String? _errorMessage;

  // Face Registration Simulation Data
  bool _faceRegistered = false;
  String? _registeredEmbedding;

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

  // Opens a simulated dialog for camera face capture and registration
  void _startFaceEnrollment() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool scanning = false;
            double progress = 0.0;
            
            void simulateScanning() async {
              setDialogState(() => scanning = true);
              for (int i = 0; i <= 10; i++) {
                await Future.delayed(const Duration(milliseconds: 250));
                setDialogState(() {
                  progress = i / 10.0;
                });
              }
              
              // Generate mock 128-float face embedding array
              final random = Random();
              final List<double> mockEmbedding = List.generate(128, (_) => (random.nextDouble() * 2) - 1);
              
              setState(() {
                _faceRegistered = true;
                _registeredEmbedding = jsonEncode(mockEmbedding);
              });
              
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Face template enrolled successfully!')),
                );
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1B29),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Enroll Face ID', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Position your face inside the frame and look directly at the camera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  
                  // Camera Capture View Frame
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scanning ? const Color(0xFF34D399) : const Color(0xFF8B5CF6),
                        width: 3
                      ),
                      color: Colors.black26,
                    ),
                    child: Center(
                      child: scanning
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(color: Color(0xFF34D399)),
                              const SizedBox(height: 10),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                              )
                            ],
                          )
                        : const Icon(Icons.face, size: 80, color: Color(0xFF8B5CF6)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  if (scanning)
                    const Text('Scanning face landmarks...', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: simulateScanning,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            minimumSize: const Size(120, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Capture'),
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
                  // App Icon / Logo
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ]
                      ),
                      child: const Icon(
                        Icons.school,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // App Title
                  Text(
                    _isLogin ? 'Welcome Back' : 'Create Account',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin 
                      ? 'Log in to manage or submit attendance' 
                      : 'Enroll and register your biometrics',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.colorScheme.error.withOpacity(0.3)),
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
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Enter your full name' : null,
                      onSaved: (val) => _name = val!.trim(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Username (or Student ID)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Enter username' : null,
                    onSaved: (val) => _username = val!.trim().toLowerCase(),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Enter password' : null,
                    onSaved: (val) => _password = val!,
                  ),
                  const SizedBox(height: 20),

                  // Role Selection and Face enrollment (During Registration)
                  if (!_isLogin) ...[
                    const Text('I am registering as a:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                                  ? const Color(0xFF8B5CF6).withOpacity(0.15) 
                                  : Colors.transparent,
                                border: Border.all(
                                  color: _role == 'student' ? const Color(0xFF8B5CF6) : const Color(0xFF2E2A3A)
                                ),
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.school, size: 24),
                                  SizedBox(height: 4),
                                  Text('Student', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
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
                                  ? const Color(0xFF8B5CF6).withOpacity(0.15) 
                                  : Colors.transparent,
                                border: Border.all(
                                  color: _role == 'teacher' ? const Color(0xFF8B5CF6) : const Color(0xFF2E2A3A)
                                ),
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: const Column(
                                children: [
                                  Icon(Icons.workspace_premium, size: 24),
                                  SizedBox(height: 4),
                                  Text('Teacher', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Student biometrics option
                    if (_role == 'student') ...[
                      InkWell(
                        onTap: _startFaceEnrollment,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _faceRegistered 
                              ? const Color(0xFF34D399).withOpacity(0.1) 
                              : const Color(0xFF8B5CF6).withOpacity(0.05),
                            border: Border.all(
                              color: _faceRegistered ? const Color(0xFF34D399) : const Color(0xFF8B5CF6).withOpacity(0.4),
                              style: BorderStyle.solid
                            ),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _faceRegistered ? Icons.check_circle : Icons.face,
                                color: _faceRegistered ? const Color(0xFF34D399) : const Color(0xFF8B5CF6),
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
                                        color: _faceRegistered ? const Color(0xFF34D399) : Colors.white,
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

                  // Action Buttons
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
                      style: const TextStyle(color: Color(0xFF8B5CF6)),
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
