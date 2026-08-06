import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';

class StudentFlowScreen extends StatefulWidget {
  const StudentFlowScreen({super.key});

  @override
  State<StudentFlowScreen> createState() => _StudentFlowScreenState();
}

class _StudentFlowScreenState extends State<StudentFlowScreen> {
  List<dynamic> _classes = [];
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  Future<void> _fetchClasses() async {
    setState(() => _isLoading = true);
    try {
      final classes = await ApiService.getUserClasses(ApiService.currentUser!['id']);
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load courses: $e')),
      );
    }
  }

  // Dialog to enroll in a new class
  void _enrollInClass() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1B29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Enroll in Class', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: codeController,
            decoration: const InputDecoration(labelText: 'Enter Course Code (e.g., CS-101)'),
            textCapitalization: TextCapitalization.characters,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (codeController.text.isEmpty) return;
                try {
                  await ApiService.enrollClass(
                    ApiService.currentUser!['id'],
                    codeController.text.trim().toUpperCase(),
                  );
                  if (context.mounted) Navigator.pop(context);
                  _fetchClasses();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Enrollment Failed: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
              child: const Text('Enroll'),
            ),
          ],
        );
      },
    );
  }

  // Trigger multi-step attendance process
  void _startAttendanceVerification() async {
    // Request required camera and bluetooth/location permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final isCameraGranted = statuses[Permission.camera] == PermissionStatus.granted;
    final isScanGranted = statuses[Permission.bluetoothScan] == PermissionStatus.granted;
    final isConnectGranted = statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
    final isLocationGranted = statuses[Permission.location] == PermissionStatus.granted ||
                             statuses[Permission.location] == PermissionStatus.limited;

    if (!isCameraGranted || !isScanGranted || !isConnectGranted || !isLocationGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera, Bluetooth, and Location permissions are required to check in.')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AttendanceWizard()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ApiService.token = null;
              ApiService.currentUser = null;
              Navigator.pushReplacementNamed(context, '/login');
            },
          )
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Student profile card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF34D399).withOpacity(0.1),
                          child: const Icon(Icons.school, color: Color(0xFF34D399), size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ApiService.currentUser!['name'],
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text('Student ID: ${ApiService.currentUser!['username']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildFaceEnrollmentAlert(),
                const SizedBox(height: 16),

                // Core Verification CTA
                ElevatedButton.icon(
                  onPressed: _startAttendanceVerification,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Mark Attendance Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Enrolled Courses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    TextButton.icon(
                      onPressed: _enrollInClass,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Enroll in Course'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF8B5CF6)),
                    )
                  ],
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: _classes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.menu_book, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 8),
                            const Text('Not enrolled in any classes yet.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _classes.length,
                        itemBuilder: (context, index) {
                          final c = _classes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white.withOpacity(0.01),
                            child: ListTile(
                              title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(c['code'], style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.w600)),
                              trailing: const Icon(Icons.check_circle_outline, color: Colors.grey, size: 20),
                            ),
                          );
                        },
                      ),
                )
              ],
            ),
          ),
    );
  }

  Widget _buildFaceEnrollmentAlert() {
    final String? enrolled = ApiService.currentUser!['face_embedding'];
    final bool isLegacy = enrolled == null || !enrolled.startsWith('{');

    return Card(
      color: isLegacy ? const Color(0x1FEEF2F6) : const Color(0x0FFF34D3),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              isLegacy ? Icons.warning_amber_rounded : Icons.face,
              color: isLegacy ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLegacy ? "Legacy Face Template" : "Biometrics Active",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isLegacy ? const Color(0xFFFBBF24) : const Color(0xFF34D399),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isLegacy 
                      ? "Please enroll a modern biometric template before taking attendance."
                      : "Your face biometric signature is enrolled and secure.",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _reEnrollFace,
              style: TextButton.styleFrom(
                backgroundColor: isLegacy ? const Color(0xFFFBBF24).withOpacity(0.1) : Colors.white10,
                foregroundColor: isLegacy ? const Color(0xFFFBBF24) : Colors.white70,
              ),
              child: Text(isLegacy ? "Enroll Now" : "Update"),
            )
          ],
        ),
      ),
    );
  }

  void _reEnrollFace() {
    bool cameraInitialized = false;
    CameraController? cameraController;
    FaceDetector? dialogFaceDetector;
    bool scanning = false;
    String statusText = "Position your face inside the frame and look directly at the camera.";

    Future<void> initCameraForEnrollment(StateSetter setDialogState) async {
      try {
        final cameras = await availableCameras();
        final frontCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );

        cameraController = CameraController(
          frontCamera,
          ResolutionPreset.medium,
          enableAudio: false,
        );

        await cameraController!.initialize();
        
        dialogFaceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            enableLandmarks: true,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );

        setDialogState(() {
          cameraInitialized = true;
        });
      } catch (e) {
        debugPrint("Error initializing camera for re-enrollment: $e");
      }
    }

    void disposeCameraForEnrollment() {
      cameraController?.dispose();
      cameraController = null;
      cameraInitialized = false;
      dialogFaceDetector?.close();
      dialogFaceDetector = null;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!cameraInitialized && cameraController == null) {
              initCameraForEnrollment(setDialogState);
            }

            void captureAndProcessFace() async {
              if (cameraController == null || !cameraInitialized) return;
              
              setDialogState(() {
                scanning = true;
                statusText = "Capturing image...";
              });
              
              try {
                final XFile imageFile = await cameraController!.takePicture();
                
                setDialogState(() {
                  statusText = "Analyzing facial landmarks...";
                });
                
                final inputImage = InputImage.fromFilePath(imageFile.path);
                final List<Face> faces = await dialogFaceDetector!.processImage(inputImage);
                
                if (faces.isEmpty) {
                  throw Exception("No face detected. Position your face inside the oval and try again.");
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
                final String serializedRatios = jsonEncode(ratios);
                
                final uid = ApiService.currentUser!['id'];
                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                  'face_embedding': serializedRatios,
                });
                
                setState(() {
                  ApiService.currentUser!['face_embedding'] = serializedRatios;
                });
                
                disposeCameraForEnrollment();
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('Face template updated successfully!')),
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
                'Update Face ID', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
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
                        color: scanning ? const Color(0xFF34D399) : const Color(0xFF8B5CF6),
                        width: 3
                      ),
                      color: Colors.black26,
                    ),
                    child: ClipOval(
                      child: (cameraInitialized && cameraController != null && cameraController!.value.isInitialized)
                          ? AspectRatio(
                              aspectRatio: 1.0,
                              child: CameraPreview(cameraController!),
                            )
                          : const Center(
                              child: CircularProgressIndicator(color: Color(0xFF8B5CF6)),
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
                            disposeCameraForEnrollment();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: (cameraInitialized && cameraController != null && cameraController!.value.isInitialized)
                              ? captureAndProcessFace
                              : null,
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
          },
        );
      },
    );
  }
}

// MULTI-STEP ATTENDANCE VERIFICATION WIZARD
class AttendanceWizard extends StatefulWidget {
  const AttendanceWizard({super.key});

  @override
  State<AttendanceWizard> createState() => _AttendanceWizardState();
}

class _AttendanceWizardState extends State<AttendanceWizard> {
  int _currentStep = 0; // 0: Face, 1: QR Scan, 2: BLE scan + Submit, 3: Success

  // Step 1: Face Detector States
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  CameraDescription? _cameraDescription;
  bool _isDetecting = false;
  bool _faceLivenessPassed = false;
  String _livenessInstruction = "Position your face in the oval";
  
  // Liveness validation checks
  bool _blinkPrompted = false;
  bool _blinkDone = false;

  // Step 2: Scanned Data
  String? _scannedSessionId;
  String? _scannedOtpToken;
  String? _submissionError;
  bool _matchingFeatures = false;
  double _matchPercentage = 0.0;

  // Step 3: BLE Scan States
  bool _bleProximityPassed = false;
  String _bleStatusText = "Initializing Bluetooth Scan...";
  StreamSubscription? _bleScanSubscription;

  @override
  void initState() {
    super.initState();
    _initStepFlow();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    _bleScanSubscription?.cancel();
    super.dispose();
  }

  void _initStepFlow() {
    if (_currentStep == 0) {
      _initCameraAndFaceDetection();
    }
  }

  // STEP 1: INITIALIZE CAMERA AND FACE DETECTOR FOR LIVENESS CHECK
  Future<void> _initCameraAndFaceDetection() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _cameraDescription = frontCamera;

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _cameraController!.initialize();
    
    // Initialize Google ML Kit Face Detector with classification and landmark options enabled
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Enables eyes-open / smile ratios
        enableLandmarks: true,       // Enables landmarks for geometric matching
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    if (mounted) setState(() {});

    // Start processing camera stream frames
    _cameraController!.startImageStream((CameraImage image) {
      if (_isDetecting || _faceLivenessPassed) return;
      _isDetecting = true;
      _detectFace(image);
    });
  }

  InputImageRotation? _getRotation(CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = orientations[_cameraController!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    return rotation;
  }

  Future<void> _detectFace(CameraImage image) async {
    try {
      if (_cameraDescription == null || _cameraController == null) return;

      final rotation = _getRotation(_cameraDescription!);
      if (rotation == null) {
        _isDetecting = false;
        return;
      }

      final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
      final plane = image.planes.first;

      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );

      final List<Face> faces = await _faceDetector!.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _livenessInstruction = "Face not found. Keep phone steady.";
        });
        _isDetecting = false;
        return;
      }

      final Face face = faces.first;

      // Ensure face occupies enough screen space (isn't too far away)
      if (face.boundingBox.width < 100) {
        setState(() => _livenessInstruction = "Move closer to the camera");
        _isDetecting = false;
        return;
      }

      // Step-by-Step Liveness checks
      if (!_blinkPrompted) {
        // Step 1: Prompt blink
        setState(() {
          _blinkPrompted = true;
          _livenessInstruction = "Liveness check: Blink your eyes once";
        });
      }

      if (_blinkPrompted && !_blinkDone) {
        double leftEye = face.leftEyeOpenProbability ?? 1.0;
        double rightEye = face.rightEyeOpenProbability ?? 1.0;
        
        // Probability threshold: < 0.2 means closed
        if (leftEye < 0.2 && rightEye < 0.2) {
          _blinkDone = true;
          _cameraController!.stopImageStream();
          
          double calculatedScore = 0.0;
          try {
            final String? enrolledEmbedding = ApiService.currentUser!['face_embedding'];
            debugPrint("ENROLLED EMBEDDING IN DB: $enrolledEmbedding");
            if (enrolledEmbedding == null) {
              throw Exception("No face enrolled. Please register your face first.");
            }
            
            final Map<String, dynamic> enrolled = jsonDecode(enrolledEmbedding);
            final double e1 = enrolled['r1'] ?? 0.0;
            final double e2 = enrolled['r2'] ?? 0.0;
            
            final leftEye = face.landmarks[FaceLandmarkType.leftEye];
            final rightEye = face.landmarks[FaceLandmarkType.rightEye];
            final nose = face.landmarks[FaceLandmarkType.noseBase];
            
            debugPrint("LIVE LANDMARKS: leftEye=$leftEye, rightEye=$rightEye, nose=$nose");
            
            if (leftEye == null || rightEye == null || nose == null) {
              throw Exception("Landmarks not clear. Hold still and look directly at camera.");
            }
            
            final double dEyes = sqrt(pow(rightEye.position.x - leftEye.position.x, 2) + pow(rightEye.position.y - leftEye.position.y, 2));
            final double dLeftEyeNose = sqrt(pow(nose.position.x - leftEye.position.x, 2) + pow(nose.position.y - leftEye.position.y, 2));
            final double dRightEyeNose = sqrt(pow(nose.position.x - rightEye.position.x, 2) + pow(nose.position.y - rightEye.position.y, 2));
            
            if (dLeftEyeNose == 0.0 || dRightEyeNose == 0.0) {
              throw Exception("Face alignment failed.");
            }
            
            final double r1 = dEyes / dLeftEyeNose;
            final double r2 = dEyes / dRightEyeNose;
            
            final double diff1 = (r1 - e1).abs();
            final double diff2 = (r2 - e2).abs();
            
            calculatedScore = (1.0 - (diff1 + diff2) / 1.0) * 100.0;
            if (calculatedScore > 100.0) calculatedScore = 100.0;
            if (calculatedScore < 0.0) calculatedScore = 0.0;
            
            if (calculatedScore < 80.0) {
              _submissionError = "Face verification failed (Similarity score: ${calculatedScore.toStringAsFixed(1)}%). Live facial landmarks do not match your registered face template.";
            }
            
            debugPrint("ENROLLED: r1=$e1, r2=$e2. LIVE: r1=$r1, r2=$r2. SCORE: $calculatedScore");
          } catch (e) {
            debugPrint("Biometric extraction error: $e");
            calculatedScore = 0.0;
            _submissionError = "Biometric mismatch error: $e";
          }
          
          setState(() {
            _matchingFeatures = true;
            _livenessInstruction = "Comparing with enrolled template...";
          });
          
          _runMatchingSimulation(calculatedScore);
        }
      }
    } catch (e) {
      debugPrint("Face detection error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  void _runMatchingSimulation(double calculatedScore) {
    double target = calculatedScore;
    const int steps = 15;
    double increment = target / steps;
    int currentStep = 0;

    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      currentStep++;
      setState(() {
        _matchPercentage = (increment * currentStep).clamp(0.0, target);
        _livenessInstruction = "Comparing facial features... ${_matchPercentage.toStringAsFixed(1)}%";
      });

      if (currentStep >= steps) {
        timer.cancel();
        
        // Threshold: 80% similarity required to pass
        final bool isMatch = target >= 80.0;
        
        setState(() {
          if (isMatch) {
            _faceLivenessPassed = true;
            _livenessInstruction = "Face Verified! Match: ${_matchPercentage.toStringAsFixed(1)}%";
          } else {
            _faceLivenessPassed = false;
            _livenessInstruction = "Face Mismatch! Match: ${_matchPercentage.toStringAsFixed(1)}%";
          }
        });

        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            if (isMatch) {
              setState(() {
                _currentStep = 1; // Transition to Step 2 (QR Scan)
              });
            } else {
              // Transition to failure layout
              setState(() {
                _submissionError ??= "Face verification failed (Similarity score: ${_matchPercentage.toStringAsFixed(1)}%). Live facial landmarks do not match your registered face template.";
                _currentStep = 2; // Transition to Failure UI
              });
            }
          }
        });
      }
    });
  }

  // STEP 2: HANDLERS FOR QR SCAN
  void _onQRScanned(BarcodeCapture capture) {
    if (_scannedSessionId != null) return; // Prevent double trigger
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;
    
    final String rawValue = barcodes.first.rawValue!;
    debugPrint("SCANNED QR CODE RAW VALUE: $rawValue");
    try {
      final Map<String, dynamic> data = jsonDecode(rawValue);
      
      if (data.containsKey('session_id') && data.containsKey('token')) {
        setState(() {
          _scannedSessionId = data['session_id'].toString();
          _scannedOtpToken = data['token'].toString();
          _currentStep = 2; // Transition to BLE Verification
        });
        
        // Get active BLE UUID details first, then scan BLE
        _verifyBleProximity();
      } else {
        debugPrint("QR Code does not contain expected keys: $data");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code format. Scan the projector screen.')),
        );
      }
    } catch (e) {
      debugPrint("QR Decode Error: $e, Raw Value: $rawValue");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid QR code format. Scan the projector screen.')),
      );
    }
  }

  // STEP 3: BLUETOOTH PROXIMITY SEARCH
  Future<void> _verifyBleProximity() async {
    setState(() {
      _bleStatusText = "Connecting to classroom BLE beacon...";
    });

    try {
      // 1. Double check Bluetooth is enabled
      if (!await FlutterBluePlus.isSupported) {
        throw Exception("Bluetooth is not supported on this device.");
      }

      // Check if Bluetooth is turned on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        setState(() {
          _bleStatusText = "Please turn on your Bluetooth.";
        });
        return;
      }

      bool deviceFound = false;
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      _bleScanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final String localName = r.advertisementData.localName;
          final String advName = r.advertisementData.advName;
          final String platformName = r.device.platformName;
          final String serviceUuids = r.advertisementData.serviceUuids.toString();
          final int rssi = r.rssi;
          
          debugPrint("Scanned BLE: advName='$advName', localName='$localName', platformName='$platformName', uuids='$serviceUuids', RSSI: $rssi");
          
          // Check if advertisement matches teacher classroom beacon pattern
          final bool isSmartAtt = localName.contains("SmartAtt") || 
                                  advName.contains("SmartAtt") || 
                                  platformName.contains("SmartAtt") ||
                                  (r.advertisementData.serviceUuids.isNotEmpty);
          
          if (isSmartAtt) {
            deviceFound = true;
            
            // Proximity threshold: -85 dBm reliably covers classroom range (8-10m)
            if (rssi >= -85) {
              _bleScanSubscription?.cancel();
              FlutterBluePlus.stopScan();
              
              setState(() {
                _bleProximityPassed = true;
                _bleStatusText = "Proximity confirmed! (Strength: $rssi dBm)";
              });

              // Final step: Submit attendance payload to backend
              _submitAttendanceCheckin();
              break;
            } else {
              setState(() {
                _bleStatusText = "Signal detected but too weak ($rssi dBm). Move closer to teacher.";
              });
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 8));
      
      if (!deviceFound && !_bleProximityPassed) {
        setState(() {
          _bleStatusText = "Teacher beacon not found. Ensure teacher session is active and Bluetooth is enabled on teacher's phone.";
        });
      }

    } catch (e) {
      setState(() {
        _bleStatusText = "BLE Scan failed: ${e.toString().replaceAll("Exception: ", "")}";
      });
    }
  }

  // STEP 4: SUBMIT RECORD
  Future<void> _submitAttendanceCheckin() async {
    setState(() {
      _submissionError = null;
      _bleStatusText = "Registering attendance on server...";
    });

    try {
      await ApiService.submitAttendance(
        sessionId: _scannedSessionId!,
        studentId: ApiService.currentUser!['id'],
        otpToken: _scannedOtpToken!,
        verifiedProximity: true,
        verifiedFace: true,
      );

      setState(() {
        _currentStep = 3; // Success checkmark view!
      });

    } catch (e) {
      final errorMsg = e.toString().replaceAll("Exception: ", "");
      setState(() {
        _submissionError = errorMsg;
        _bleStatusText = "Failed to mark: $errorMsg";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Flow')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stepper Headers
            _buildStepperHeader(),
            const SizedBox(height: 30),

            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: _buildCurrentStepContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Stepper Header helper
  Widget _buildStepperHeader() {
    return Row(
      children: [
        _stepIndicator(0, 'Face ID', _currentStep >= 0),
        _stepConnector(_currentStep > 0),
        _stepIndicator(1, 'Scan QR', _currentStep >= 1),
        _stepConnector(_currentStep > 1),
        _stepIndicator(2, 'Proximity', _currentStep >= 2),
      ],
    );
  }

  Widget _stepIndicator(int index, String label, bool active) {
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: active 
              ? const Color(0xFF8B5CF6) 
              : const Color(0xFF2E2A3A),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: active ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 10, color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _stepConnector(bool active) {
    return Container(
      width: 40,
      height: 2,
      color: active ? const Color(0xFF8B5CF6) : const Color(0xFF2E2A3A),
    );
  }

  // Render current active step widget layout
  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        // Face detection view
        if (_cameraController == null || !_cameraController!.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _livenessInstruction,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Camera feed framed inside a neat oval/mask
            ClipOval(
              child: SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),
                    if (_matchingFeatures) ...[
                      const _ScanningOverlay(),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Checking items indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _checkIndicator('Eyes Blink', _blinkDone),
              ],
            )
          ],
        );

      case 1:
        // QR scanner view
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Scan Classroom QR Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text('Focus on the dynamic QR code displayed on the screen.', style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 24),
            
            // Mobile QR scanner camera preview widget
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 250,
                height: 250,
                child: MobileScanner(
                  onDetect: _onQRScanned,
                ),
              ),
            ),
          ],
        );

      case 2:
        // BLE validation progress
        if (_submissionError != null) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 60),
              const SizedBox(height: 24),
              const Text(
                'Registration Failed',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 8),
              Text(
                _submissionError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      final bool isFaceError = _submissionError != null && (_submissionError!.contains("face") || _submissionError!.contains("Face"));
                      setState(() {
                        _submissionError = null;
                      });
                      if (isFaceError) {
                        setState(() {
                          _currentStep = 0;
                          _faceLivenessPassed = false;
                          _blinkPrompted = false;
                          _blinkDone = false;
                          _matchingFeatures = false;
                          _matchPercentage = 0.0;
                          _isDetecting = false;
                        });
                        _initCameraAndFaceDetection();
                      } else {
                        _submitAttendanceCheckin();
                      }
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
                    child: const Text('Try Again'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, 44),
                      side: const BorderSide(color: Colors.grey),
                    ),
                    child: const Text('Exit', style: TextStyle(color: Colors.white)),
                  ),
                ],
              )
            ],
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF8B5CF6)),
            const SizedBox(height: 24),
            Text(
              _bleStatusText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('Scanning for localized classroom Bluetooth frequencies...', style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(height: 20),
            if (!_bleProximityPassed) ...[
              ElevatedButton(
                onPressed: _verifyBleProximity,
                style: ElevatedButton.styleFrom(minimumSize: const Size(140, 44)),
                child: const Text('Retry BLE Scan'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  _bleScanSubscription?.cancel();
                  FlutterBluePlus.stopScan();
                  setState(() {
                    _bleProximityPassed = true;
                    _bleStatusText = "Proximity Bypassed (Demo)";
                  });
                  _submitAttendanceCheckin();
                },
                icon: const Icon(Icons.speed, color: Colors.amber, size: 18),
                label: const Text('Bypass Proximity for Demo', style: TextStyle(color: Colors.amber)),
              )
            ]
          ],
        );

      case 3:
        // Success Animation View
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF34D399),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'Attendance Logged!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF34D399)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your details, face token, and room proximity have been verified and submitted.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to Dashboard'),
            )
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _checkIndicator(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? const Color(0xFF34D399) : Colors.grey,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: done ? Colors.white : Colors.grey, fontSize: 13)),
      ],
    );
  }
}

class _ScanningOverlay extends StatefulWidget {
  const _ScanningOverlay();

  @override
  State<_ScanningOverlay> createState() => _ScanningOverlayState();
}

class _ScanningOverlayState extends State<_ScanningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          children: [
            Positioned(
              top: _controller.value * 220,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34D399).withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFF34D399).withOpacity(0.05),
            ),
          ],
        );
      },
    );
  }
}
