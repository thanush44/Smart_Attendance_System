import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
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
      debugPrint("TeacherHomeScreen _fetchClasses loaded: $classes");
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e, stack) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("TeacherHomeScreen _fetchClasses Error: $e");
      debugPrint("TeacherHomeScreen Stack trace: $stack");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading classes: $e')),
      );
    }
  }

  // Dialog to create a new class
  void _createNewClass() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1B29),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Create New Class', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Class Name (e.g., Computer Science I)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Class Code (e.g., CS-101)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || codeController.text.isEmpty) return;
                try {
                  await ApiService.createClass(
                    name: nameController.text.trim(),
                    code: codeController.text.trim().toUpperCase(),
                    teacherId: ApiService.currentUser!['id'],
                  );
                  if (context.mounted) Navigator.pop(context);
                  _fetchClasses();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  // Request Bluetooth permissions (needed for BLE peripheral mode on Android)
  Future<bool> _requestBlePermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final locationGranted = (statuses[Permission.location]?.isGranted ?? false) ||
                              (statuses[Permission.location]?.isLimited ?? false);

      return locationGranted;
    } catch (e) {
      debugPrint("BLE permission request error: $e");
      return true;
    }
  }

  void _showClassOptions(Map<String, dynamic> classData) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1B29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_circle_fill, color: Color(0xFF34D399)),
                title: const Text('Start/Manage Session'),
                onTap: () {
                  Navigator.pop(context);
                  _openClassSession(classData);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Color(0xFF8B5CF6)),
                title: const Text('View Attendance History'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClassAttendanceHistoryScreen(classData: classData),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Navigate to Class Active Session control screen
  void _openClassSession(Map<String, dynamic> classData) async {
    bool permissionsGranted = await _requestBlePermissions();
    if (!permissionsGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth & Location permissions are required to host a session.')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveSessionScreen(classData: classData),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.clearUserSession();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          )
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                          child: const Icon(Icons.person, size: 30, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, Prof. ${ApiService.currentUser!['name']}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text('Manage classroom rosters and track check-ins.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Active Courses',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: _createNewClass,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Course'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF8B5CF6)),
                    )
                  ],
                ),
                const SizedBox(height: 10),

                Expanded(
                  child: _classes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.class_outlined, size: 60, color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 10),
                            const Text('No courses created yet.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _classes.length,
                        itemBuilder: (context, index) {
                          final c = _classes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              title: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(c['code'], style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
                              trailing: const Icon(Icons.more_vert, color: Colors.grey, size: 24),
                              onTap: () => _showClassOptions(c),
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

// ACTIVE SESSION CONTROL SCREEN
class ActiveSessionScreen extends StatefulWidget {
  final Map<String, dynamic> classData;
  const ActiveSessionScreen({super.key, required this.classData});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  
  bool _sessionStarted = false;
  Map<String, dynamic>? _sessionData;
  List<dynamic> _checkins = [];
  Timer? _pollingTimer;
  bool _isAdvertising = false;
  bool _checkingActiveSession = true;
  StreamSubscription<PeripheralState>? _bleStateSubscription;
  String? _bleError;

  @override
  void initState() {
    super.initState();
    _checkActiveSession();
    _listenToBleState();
  }

  void _listenToBleState() {
    try {
      _bleStateSubscription = _blePeripheral.onPeripheralStateChanged?.listen((state) {
        if (!mounted) return;
        debugPrint("BLE state changed: $state");
        setState(() {
          _isAdvertising = (state == PeripheralState.advertising);
          switch (state) {
            case PeripheralState.poweredOff:
              _bleError = "Bluetooth is turned off on your device.";
              break;
            case PeripheralState.unsupported:
              _bleError = "BLE Advertising is not supported on this device.";
              break;
            case PeripheralState.unauthorized:
              _bleError = "Bluetooth permissions are not authorized.";
              break;
            default:
              _bleError = null;
          }
        });
      });
    } catch (e) {
      debugPrint("Error listening to BLE state: $e");
    }
  }

  Future<bool> _requestBlePermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final locationGranted = (statuses[Permission.location]?.isGranted ?? false) ||
                              (statuses[Permission.location]?.isLimited ?? false);

      return locationGranted;
    } catch (e) {
      debugPrint("BLE permission request error: $e");
      return true;
    }
  }

  Future<void> _checkActiveSession() async {
    try {
      final activeSession = await ApiService.getActiveSession(widget.classData['id']);
      if (activeSession != null && mounted) {
        setState(() {
          _sessionData = activeSession;
          _sessionStarted = true;
          _checkingActiveSession = false;
        });

        // Request BLE permissions first
        final permissionsGranted = await _requestBlePermissions();
        if (permissionsGranted) {
          // Start BLE Peripheral Advertising
          await _startBleAdvertising(activeSession['ble_uuid']);
        } else {
          setState(() {
            _bleError = "Bluetooth permissions are required to advertise.";
          });
        }

        // Poll attendance list periodically (every 3 seconds)
        _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _fetchAttendanceList();
        });
        
        _fetchAttendanceList();
      } else {
        if (mounted) {
          setState(() {
            _checkingActiveSession = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking active session: $e");
      if (mounted) {
        setState(() {
          _checkingActiveSession = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _bleStateSubscription?.cancel();
    _stopBleAdvertising();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() => _sessionStarted = false);
    try {
      // 1. Register Session on Backend
      final data = await ApiService.startSession(widget.classData['id']);
      
      setState(() {
        _sessionData = data;
        _sessionStarted = true;
      });

      // 2. Request permissions and start BLE Peripheral Advertising
      final permissionsGranted = await _requestBlePermissions();
      if (permissionsGranted) {
        await _startBleAdvertising(data['ble_uuid']);
      } else {
        setState(() {
          _bleError = "Bluetooth permissions are required to advertise.";
        });
      }

      // 3. Poll attendance list periodically (every 3 seconds)
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _fetchAttendanceList();
      });
      
      _fetchAttendanceList();

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initiate class session: $e')),
      );
    }
  }

  // Turn on BLE broadcasting
  Future<void> _startBleAdvertising(String uuid) async {
    try {
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: uuid,
        localName: 'SmartAtt_${widget.classData['code']}',
        includeDeviceName: true,
      );
      
      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() {
        _isAdvertising = true;
        _bleError = null;
      });
    } catch (e) {
      debugPrint("BLE Advertising Error: $e");
      setState(() {
        _bleError = "Failed to start BLE advertising: ${e.toString().replaceAll("Exception: ", "")}";
      });
    }
  }

  // Turn off BLE broadcasting
  Future<void> _stopBleAdvertising() async {
    try {
      await _blePeripheral.stop();
      if (mounted) {
        setState(() {
          _isAdvertising = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to stop BLE advertising: $e");
    }
  }

  // Sync latest checked-in students
  Future<void> _fetchAttendanceList() async {
    if (_sessionData == null) return;
    try {
      final list = await ApiService.getSessionAttendance(_sessionData!['session_id']);
      setState(() {
        _checkins = list;
      });
    } catch (e) {
      debugPrint("Polling check-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.classData['name']),
      ),
      body: _checkingActiveSession
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            key: ValueKey(_sessionStarted),
            child: !_sessionStarted
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors, size: 80, color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Ready to Start Attendance',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Starting attendance will turn on your phone\'s Bluetooth beacon and generate a dynamic check-in link for the projector.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _startSession,
                    child: const Text('Start Attendance Session'),
                  )
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // BLE Beacon Active Card
                GestureDetector(
                  onTap: _isAdvertising ? null : () async {
                    if (_sessionData != null) {
                      final permissionsGranted = await _requestBlePermissions();
                      if (permissionsGranted) {
                        await _startBleAdvertising(_sessionData!['ble_uuid']);
                      }
                    }
                  },
                  child: Card(
                    color: const Color(0xFF1E1B29),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isAdvertising ? Icons.sensors : Icons.sensors_off,
                                color: _isAdvertising ? const Color(0xFF34D399) : Colors.red,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isAdvertising ? 'Broadcasting BLE Beacon' : 'BLE Beacon Suspended',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _isAdvertising ? const Color(0xFF34D399) : Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isAdvertising 
                                          ? 'Proximity check is active.' 
                                          : (_bleError ?? 'Bluetooth advertising is inactive. Tap to retry.'),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, color: Color(0xFF2E2A3A)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Projector Session PIN (Short):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_sessionData!['short_id'] ?? 'N/A'}',
                                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF34D399), letterSpacing: 1),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Color(0xFF8B5CF6)),
                                tooltip: 'Copy Session PIN',
                                onPressed: () {
                                  final pin = _sessionData!['short_id'] ?? '';
                                  Clipboard.setData(ClipboardData(text: pin));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Session PIN copied to clipboard!')),
                                  );
                                },
                              )
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Full Session ID:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Row(
                                children: [
                                  Text(
                                    '${_sessionData!['session_id']}',
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: _sessionData!['session_id']));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Full Session ID copied!')),
                                      );
                                    },
                                    child: const Icon(Icons.copy, size: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Open the Web Dashboard on the projector and enter the Session PIN above to display the rolling QR code.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                            textAlign: TextAlign.center,
                          )
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Attendance title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Present Students', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34D399).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.3))
                      ),
                      child: Text(
                        '${_checkins.length} Present',
                        style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 10),

                // Attendance List
                Expanded(
                  child: _checkins.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No check-ins yet. Waiting for students...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _checkins.length,
                        itemBuilder: (context, index) {
                          final c = _checkins[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white.withValues(alpha: 0.02),
                            child: ListTile(
                              dense: true,
                              title: Text(c['student_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(c['student_username'], style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.face, size: 16, color: Color(0xFF34D399)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.bluetooth, size: 16, color: Color(0xFF34D399)),
                                  const SizedBox(width: 12),
                                  Text(
                                    c['timestamp'].toString().split('T')[1].substring(0, 5),
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: () async {
                    _pollingTimer?.cancel();
                    await _stopBleAdvertising();
                    if (_sessionData != null) {
                      try {
                        await ApiService.endSession(_sessionData!['session_id']);
                      } catch (e) {
                        debugPrint("Error ending session in Firestore: $e");
                      }
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attendance session completed successfully.')),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.error),
                  child: const Text('Close Attendance Session'),
                )
              ],
            ),
      ),
    );
  }
}

class ClassAttendanceHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> classData;
  const ClassAttendanceHistoryScreen({super.key, required this.classData});

  @override
  State<ClassAttendanceHistoryScreen> createState() => _ClassAttendanceHistoryScreenState();
}

class _ClassAttendanceHistoryScreenState extends State<ClassAttendanceHistoryScreen> {
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedTabIndex = 0; // 0: Sessions View, 1: Student Roster View

  List<Map<String, dynamic>> _enrolledStudents = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _attendanceLogs = [];

  List<Map<String, dynamic>> _sessionGroups = [];
  List<Map<String, dynamic>> _studentStats = [];

  int _totalSessionsCount = 0;
  int _totalEnrolledCount = 0;
  double _overallAttendancePercentage = 0.0;
  int _atRiskStudentsCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final payload = await ApiService.getClassAnalyticsData(widget.classData['id']);
      if (!mounted) return;

      setState(() {
        _enrolledStudents = List<Map<String, dynamic>>.from(payload['enrolled_students']);
        _sessions = List<Map<String, dynamic>>.from(payload['sessions']);
        _attendanceLogs = List<Map<String, dynamic>>.from(payload['attendance_logs']);
        
        _processAnalyticsData();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading class analytics data: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load class analytics: $e')),
      );
    }
  }

  void _processAnalyticsData() {
    _totalEnrolledCount = _enrolledStudents.length;

    // Build unique sessions map from sessions collection + logs fallback
    Map<String, Map<String, dynamic>> sessionsMap = {};

    for (var s in _sessions) {
      final String sid = s['id'].toString();
      sessionsMap[sid] = {
        'session_id': sid,
        'short_id': s['short_id'] ?? sid.substring(0, min(6, sid.length)),
        'start_time_iso': s['start_time_iso'] ?? '',
        'is_active': s['is_active'] ?? false,
      };
    }

    // Collect sessions from logs if any exist outside explicit session docs
    for (var log in _attendanceLogs) {
      final String sid = (log['session_id'] ?? '').toString();
      if (sid.isNotEmpty && !sessionsMap.containsKey(sid)) {
        sessionsMap[sid] = {
          'session_id': sid,
          'short_id': sid.length > 6 ? sid.substring(0, 6) : sid,
          'start_time_iso': log['timestamp'] ?? '',
          'is_active': false,
        };
      }
    }

    final List<Map<String, dynamic>> sessionList = sessionsMap.values.toList();
    sessionList.sort((a, b) => (b['start_time_iso'] ?? '').compareTo(a['start_time_iso'] ?? ''));
    _totalSessionsCount = sessionList.length;

    // Group logs by session_id
    Map<String, List<Map<String, dynamic>>> logsBySession = {};
    for (var log in _attendanceLogs) {
      final String sid = (log['session_id'] ?? '').toString();
      logsBySession.putIfAbsent(sid, () => []).add(log);
    }

    // 1. Build Session-Wise Roster Groups
    _sessionGroups = [];
    int grandTotalPresentLogs = 0;

    for (var s in sessionList) {
      final String sid = s['session_id'];
      final List<Map<String, dynamic>> logsForSession = logsBySession[sid] ?? [];

      // Set of student IDs present in this session
      Set<String> presentStudentIds = {};
      List<Map<String, dynamic>> presentRoster = [];

      for (var log in logsForSession) {
        final String stId = (log['student_id'] ?? '').toString();
        if (stId.isNotEmpty) {
          presentStudentIds.add(stId);
          presentRoster.add({
            'student_id': stId,
            'student_name': log['student_name'] ?? 'Student',
            'student_username': log['student_username'] ?? stId,
            'timestamp': log['timestamp'] ?? '',
            'verified_face': log['verified_face'] ?? true,
            'verified_proximity': log['verified_proximity'] ?? true,
          });
        }
      }

      grandTotalPresentLogs += presentRoster.length;

      // Identify absent students from enrolled list
      List<Map<String, dynamic>> absentRoster = [];
      for (var st in _enrolledStudents) {
        final String stId = st['id'].toString();
        if (!presentStudentIds.contains(stId)) {
          absentRoster.add(st);
        }
      }

      double sessionPct = _totalEnrolledCount > 0 
          ? (presentRoster.length / _totalEnrolledCount) * 100.0 
          : 0.0;

      String dateFormatted = 'Session Log';
      if (s['start_time_iso'] != null && s['start_time_iso'].toString().contains('T')) {
        final parts = s['start_time_iso'].toString().split('T');
        final timePart = parts[1].length >= 5 ? parts[1].substring(0, 5) : parts[1];
        dateFormatted = '${parts[0]} at $timePart';
      }

      _sessionGroups.add({
        'session_id': sid,
        'short_id': s['short_id'],
        'date_str': dateFormatted,
        'present_roster': presentRoster,
        'absent_roster': absentRoster,
        'percentage': sessionPct,
      });
    }

    // 2. Build Student-Wise Analytics Roster
    Map<String, int> studentPresentCounts = {};
    for (var log in _attendanceLogs) {
      final String stId = (log['student_id'] ?? '').toString();
      if (stId.isNotEmpty) {
        studentPresentCounts[stId] = (studentPresentCounts[stId] ?? 0) + 1;
      }
    }

    _studentStats = [];
    _atRiskStudentsCount = 0;

    for (var st in _enrolledStudents) {
      final String stId = st['id'].toString();
      final int attended = studentPresentCounts[stId] ?? 0;
      final int maxPossible = _totalSessionsCount;
      final double rate = maxPossible > 0 ? (attended / maxPossible) * 100.0 : 100.0;

      final bool isAtRisk = maxPossible > 0 && rate < 75.0;
      if (isAtRisk) _atRiskStudentsCount++;

      _studentStats.add({
        'id': stId,
        'name': st['name'] ?? 'Student',
        'username': st['username'] ?? stId,
        'attended_count': attended,
        'total_sessions': maxPossible,
        'percentage': rate,
        'is_at_risk': isAtRisk,
      });
    }

    // Overall class attendance rate calculation
    final int possibleTotalCheckins = _totalSessionsCount * _totalEnrolledCount;
    _overallAttendancePercentage = possibleTotalCheckins > 0
        ? (grandTotalPresentLogs / possibleTotalCheckins) * 100.0
        : 0.0;
  }

  Future<void> _exportCsvReport() async {
    try {
      final buffer = StringBuffer();
      final String className = widget.classData['name'] ?? 'Course';
      final String classCode = widget.classData['code'] ?? 'CS-101';

      buffer.writeln("Smart Attendance System - Class Attendance Summary Report");
      buffer.writeln("Class Name,$className");
      buffer.writeln("Course Code,$classCode");
      buffer.writeln("Total Enrolled Students,$_totalEnrolledCount");
      buffer.writeln("Total Sessions Conducted,$_totalSessionsCount");
      buffer.writeln("Overall Attendance Rate,${_overallAttendancePercentage.toStringAsFixed(1)}%");
      buffer.writeln("");
      buffer.writeln("Session PIN/ID,Date & Time,Student Name,Student ID,Status,Face Verified,BLE Proximity Verified");

      for (var group in _sessionGroups) {
        final String pin = group['short_id'] ?? '';
        final String dateStr = group['date_str'] ?? '';

        for (var p in group['present_roster']) {
          final name = (p['student_name'] ?? '').replaceAll('"', '""');
          final uname = (p['student_username'] ?? '').replaceAll('"', '""');
          buffer.writeln('"$pin","$dateStr","$name","$uname","Present","Yes","Yes"');
        }

        for (var a in group['absent_roster']) {
          final name = (a['name'] ?? '').replaceAll('"', '""');
          final uname = (a['username'] ?? '').replaceAll('"', '""');
          buffer.writeln('"$pin","$dateStr","$name","$uname","Absent","N/A","N/A"');
        }
      }

      final directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/${classCode}_Attendance_Report.csv';
      final File file = File(filePath);
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      await Share.shareXFiles([XFile(filePath)], text: '$className ($classCode) Attendance Summary Report');
    } catch (e) {
      debugPrint("CSV Export Error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String className = widget.classData['name'] ?? 'Class Details';
    final String classCode = widget.classData['code'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('$className ($classCode)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Export CSV Report',
            onPressed: _exportCsvReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Executive Metrics Summary Header
                    _buildExecutiveMetricsHeader(),
                    const SizedBox(height: 20),

                    // Live Search Bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search student or session PIN...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 16),

                    // Segmented Control (Sessions View vs Student Analytics View)
                    _buildSegmentedTabToggle(),
                    const SizedBox(height: 16),

                    // View Content
                    _selectedTabIndex == 0 
                        ? _buildSessionWiseView() 
                        : _buildStudentWiseView(),
                  ],
                ),
              ),
            ),
    );
  }

  // Executive Metric Summary Cards Header
  Widget _buildExecutiveMetricsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Course Attendance Overview',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Sessions',
                value: '$_totalSessionsCount',
                icon: Icons.event_note,
                iconColor: const Color(0xFF8B5CF6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'Avg Rate',
                value: '${_overallAttendancePercentage.toStringAsFixed(1)}%',
                icon: Icons.pie_chart_outline,
                iconColor: _overallAttendancePercentage >= 75.0
                    ? const Color(0xFF34D399)
                    : const Color(0xFFFBBF24),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Enrolled',
                value: '$_totalEnrolledCount Students',
                icon: Icons.people_outline,
                iconColor: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                title: 'At-Risk (<75%)',
                value: '$_atRiskStudentsCount Alert${_atRiskStudentsCount == 1 ? "" : "s"}',
                icon: Icons.warning_amber_rounded,
                iconColor: _atRiskStudentsCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF34D399),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: iconColor.withValues(alpha: 0.15),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // Segmented Control (By Session vs By Student)
  Widget _buildSegmentedTabToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B29),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2A3A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTabIndex = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 0 ? const Color(0xFF8B5CF6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'By Session (${_sessionGroups.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _selectedTabIndex == 0 ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTabIndex = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 1 ? const Color(0xFF8B5CF6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Student Roster (${_studentStats.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tab 1: Session-Wise Breakdown List
  Widget _buildSessionWiseView() {
    final filteredSessions = _sessionGroups.where((group) {
      if (_searchQuery.isEmpty) return true;
      final String pin = (group['short_id'] ?? '').toString().toLowerCase();
      final String dateStr = (group['date_str'] ?? '').toString().toLowerCase();
      final bool matchPresent = (group['present_roster'] as List).any((p) =>
          (p['student_name'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
          (p['student_username'] ?? '').toString().toLowerCase().contains(_searchQuery));
      return pin.contains(_searchQuery) || dateStr.contains(_searchQuery) || matchPresent;
    }).toList();

    if (filteredSessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No sessions match your search.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredSessions.length,
      itemBuilder: (context, index) {
        final group = filteredSessions[index];
        final String pin = group['short_id'] ?? 'Session';
        final String dateStr = group['date_str'] ?? '';
        final List presentList = group['present_roster'] ?? [];
        final List absentList = group['absent_roster'] ?? [];
        final double pct = group['percentage'] ?? 0.0;

        final Color pctColor = pct >= 75.0
            ? const Color(0xFF34D399)
            : (pct >= 50.0 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444));

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(
              'Session PIN: $pin',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pctColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pctColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${presentList.length}/$_totalEnrolledCount (${pct.toStringAsFixed(0)}%)',
                style: TextStyle(color: pctColor, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Verified Present (${presentList.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF34D399), fontSize: 13),
                        ),
                        const Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 16),
                      ],
                    ),
                    const SizedBox(height: 8),
                    presentList.isEmpty
                        ? const Text('No students checked in.', style: TextStyle(color: Colors.grey, fontSize: 12))
                        : Column(
                            children: presentList.map((p) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${p['student_name']} (${p['student_username']})',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const ContainerTag(label: 'Face ID', color: Color(0xFF34D399)),
                                    const SizedBox(width: 4),
                                    const ContainerTag(label: 'BLE', color: Color(0xFF8B5CF6)),
                                    const SizedBox(width: 4),
                                    const ContainerTag(label: 'TOTP', color: Colors.blueAccent),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Absent (${absentList.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 13),
                        ),
                        const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 16),
                      ],
                    ),
                    const SizedBox(height: 8),
                    absentList.isEmpty
                        ? const Text('Full attendance! All enrolled students present.', style: TextStyle(color: Color(0xFF34D399), fontSize: 12))
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: absentList.map((a) {
                              return Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                                label: Text(
                                  a['name'] ?? a['username'] ?? 'Student',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                ),
                              );
                            }).toList(),
                          ),
                    const SizedBox(height: 8),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // Tab 2: Student Roster Analytics View
  Widget _buildStudentWiseView() {
    final filteredStudents = _studentStats.where((st) {
      if (_searchQuery.isEmpty) return true;
      final name = (st['name'] ?? '').toString().toLowerCase();
      final uname = (st['username'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || uname.contains(_searchQuery);
    }).toList();

    if (filteredStudents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.person_search, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No students match your search.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final st = filteredStudents[index];
        final String name = st['name'] ?? 'Student';
        final String uname = st['username'] ?? '';
        final int attended = st['attended_count'] ?? 0;
        final int total = st['total_sessions'] ?? 0;
        final double pct = st['percentage'] ?? 0.0;
        final bool isAtRisk = st['is_at_risk'] ?? false;

        final Color barColor = pct >= 75.0
            ? const Color(0xFF34D399)
            : (pct >= 50.0 ? const Color(0xFFFBBF24) : const Color(0xFFEF4444));

        final initials = name.split(' ').map((n) => n.isNotEmpty ? n[0] : '').join().toUpperCase();

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      child: Text(
                        initials.length > 2 ? initials.substring(0, 2) : initials,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8B5CF6)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ID: $uname',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: barColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$attended / $total Attended',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? (attended / total) : 1.0,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 6,
                  ),
                ),
                if (isAtRisk) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                      SizedBox(width: 4),
                      Text(
                        'Shortage Notice: Attendance is below 75% required threshold.',
                        style: TextStyle(fontSize: 10, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                ]
              ],
            ),
          ),
        );
      },
    );
  }
}

// Small badge tag component for verification signals
class ContainerTag extends StatelessWidget {
  final String label;
  final Color color;

  const ContainerTag({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
