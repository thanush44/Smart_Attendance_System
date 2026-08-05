import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
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
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.any((status) => !status.isGranted)) {
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
                const SizedBox(height: 24),

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
  bool _isDetecting = false;
  bool _faceLivenessPassed = false;
  String _livenessInstruction = "Position your face in the oval";
  
  // Liveness validation checks
  bool _blinkPrompted = false;
  bool _smilePrompted = false;
  bool _blinkDone = false;
  bool _smileDone = false;

  // Step 2: Scanned Data
  int? _scannedSessionId;
  String? _scannedOtpToken;

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

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    
    // Initialize Google ML Kit Face Detector with classification options enabled
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // Enables eyes-open / smile ratios
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

  Future<void> _detectFace(CameraImage image) async {
    try {
      // Convert CameraImage format to InputImage for ML Kit
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = InputImageRotation.rotation270deg; // Front cam rotation correction
      final InputImageFormat inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
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
      if (!_blinkPrompted && !_smilePrompted) {
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
          setState(() {
            _smilePrompted = true;
            _livenessInstruction = "Now: Smile big for the camera!";
          });
        }
      }

      if (_smilePrompted && !_smileDone) {
        double smileProb = face.smilingProbability ?? 0.0;
        
        // Probability threshold: > 0.8 means smiling
        if (smileProb > 0.8) {
          _smileDone = true;
          _faceLivenessPassed = true;
          _cameraController!.stopImageStream();
          
          setState(() {
            _livenessInstruction = "Face Verified!";
          });
          
          // Hold success state momentarily, then advance to Step 2
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (mounted) {
              setState(() {
                _currentStep = 1; // Go to QR Scan
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Face detection error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // STEP 2: HANDLERS FOR QR SCAN
  void _onQRScanned(BarcodeCapture capture) {
    if (_scannedSessionId != null) return; // Prevent double trigger
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;
    
    try {
      final String rawValue = barcodes.first.rawValue!;
      final Map<String, dynamic> data = jsonDecode(rawValue);
      
      if (data.containsKey('session_id') && data.containsKey('token')) {
        setState(() {
          _scannedSessionId = data['session_id'];
          _scannedOtpToken = data['token'];
          _currentStep = 2; // Transition to BLE Verification
        });
        
        // Get active BLE UUID details first, then scan BLE
        _verifyBleProximity();
      }
    } catch (e) {
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

      // We need to fetch the class's session details from API to know which BLE UUID we are scanning for
      final classes = await ApiService.getUserClasses(ApiService.currentUser!['id']);
      // We search classes list or look for active BLE UUID from the scanned session
      // Wait, we can modify backend or simply scan for the BLE signal matching the format
      // To simplify, we scan for 4 seconds for any BLE devices matching prefix "SmartAtt_"
      
      bool deviceFound = false;
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      _bleScanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final String localName = r.advertisementData.localName;
          final String serviceUuids = r.advertisementData.serviceUuids.toString();
          final int rssi = r.rssi;
          
          debugPrint("Scanned BLE: $localName, RSSI: $rssi");
          
          // Verify if it represents our class beacon
          // (Usually named: SmartAtt_[ClassCode] or contains the matching service UUID)
          if (localName.startsWith("SmartAtt_")) {
            deviceFound = true;
            
            // Check proximity threshold: -75 dBm is generally within 6-8 meters indoors.
            if (rssi >= -75) {
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

      await Future.delayed(const Duration(seconds: 4));
      
      if (!deviceFound && !_bleProximityPassed) {
        setState(() {
          _bleStatusText = "Teacher beacon not found. Ensure you are sitting in the classroom and try again.";
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
      setState(() {
        _bleStatusText = "Failed to mark: ${e.toString().replaceAll("Exception: ", "")}";
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
                child: CameraPreview(_cameraController!),
              ),
            ),
            const SizedBox(height: 20),
            
            // Checking items indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _checkIndicator('Eyes Blink', _blinkDone),
                const SizedBox(width: 24),
                _checkIndicator('Smile Ratio', _smileDone),
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
