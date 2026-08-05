import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
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
      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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

  // Request Bluetooth and Location permissions (needed for BLE peripheral mode on Android)
  Future<bool> _requestBlePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
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
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
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
                            Icon(Icons.class_outlined, size: 60, color: Colors.white.withOpacity(0.2)),
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
                              trailing: const Icon(Icons.play_circle_fill, color: Color(0xFF8B5CF6), size: 32),
                              onTap: () => _openClassSession(c),
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
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

      // 2. Start BLE Peripheral Advertising
      await _startBleAdvertising(data['ble_uuid']);

      // 3. Poll attendance list periodically (every 3 seconds)
      _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _fetchAttendanceList();
      });
      
      _fetchAttendanceList();

    } catch (e) {
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
      );
      
      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() => _isAdvertising = true);
    } catch (e) {
      debugPrint("BLE Advertising Error: $e");
    }
  }

  // Turn off BLE broadcasting
  Future<void> _stopBleAdvertising() async {
    try {
      if (await _blePeripheral.isAdvertising) {
        await _blePeripheral.stop();
      }
      setState(() => _isAdvertising = false);
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        key: ValueKey(_sessionStarted),
        child: !_sessionStarted
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sensors, size: 80, color: const Color(0xFF8B5CF6).withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Ready to Start Attendance',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onBackground),
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
                Card(
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
                                  const Text('Proximity check is active.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24, color: Color(0xFF2E2A3A)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Projector Session ID:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            Text(
                              '${_sessionData!['session_id']}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: theme.colorScheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Open the Web Dashboard on the projector and enter the Session ID above to display the rolling QR code.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.center,
                        )
                      ],
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
                        color: const Color(0xFF34D399).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF34D399).withOpacity(0.3))
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
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.people_outline, size: 40, color: Colors.grey),
                            const SizedBox(height: 8),
                            const Text('No check-ins yet. Waiting for students...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _checkins.length,
                        itemBuilder: (context, index) {
                          final c = _checkins[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white.withOpacity(0.02),
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
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Attendance session completed successfully.')),
                      );
                    }
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
