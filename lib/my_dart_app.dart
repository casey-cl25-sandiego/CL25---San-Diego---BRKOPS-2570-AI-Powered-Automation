import 'package:flutter/material.dart';
import 'services/api_service.dart';

/// Shared model for Device and Issue
class Device {
  final String uuid;
  final String name;
  final String ip;

  Device({required this.uuid, required this.name, required this.ip});
}

class Issue {
  final String priority;
  final String description;
  final String affectedDevice;
  final DateTime lastOccurrence;

  Issue({
    required this.priority,
    required this.description,
    required this.affectedDevice,
    required this.lastOccurrence,
  });
}

/// Main StatefulWidget implementing the UI.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool loading = true;
  String? error;
  List<Device> devices = [];
  List<Issue> issues = [];
  Device? selectedDevice;
  String cliOutput = "";
  final TextEditingController commandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Authenticate and obtain token
      String token = await ApiService.authenticate();
      print("Authentication successful. Token: $token");

      // Retrieve network devices
      devices = await ApiService.getDevices(token);
      print("Retrieved ${devices.length} devices.");
      for (var d in devices) {
        print("Device: ${d.name} - ${d.ip}");
      }
      if (devices.isNotEmpty) {
        selectedDevice = devices.first;
      }

      // Retrieve issues
      issues = await ApiService.getIssues(token);
      print("Retrieved ${issues.length} issues.");
      for (var i in issues) {
        print(
            "Issue: ${i.priority} - ${i.description} - ${i.affectedDevice} - ${i.lastOccurrence}");
      }
    } catch (e) {
      print("Error during initialization: $e");
      error = e.toString();
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _runCommand() async {
    if (selectedDevice == null || commandController.text.trim().isEmpty) return;

    setState(() {
      loading = true;
      error = null;
      cliOutput = "";
    });

    try {
      String token = await ApiService.authenticate();
      String output = await ApiService.runCommand(
          token, selectedDevice!.uuid, commandController.text.trim());
      setState(() {
        cliOutput = output;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      primaryColor: const Color(0xFF1E88E5),
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF1E88E5),
        secondary: const Color(0xFF9C27B0),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Color(0xFFE0E0E0)),
      ),
    );

    return MaterialApp(
      title: "Catalyst CLI Executor",
      theme: darkTheme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Catalyst CLI Executor"),
          backgroundColor: darkTheme.primaryColor,
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child:
                        Text(error!, style: const TextStyle(color: Colors.red)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Issue Banners Section
                        ...issues.map(
                          (issue) => Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(8),
                            color: Colors.amber,
                            child: Text(
                              "Priority: ${issue.priority}\nDescription: ${issue.description}\nAffected Device: ${issue.affectedDevice}\nTime: ${_formatTime(issue.lastOccurrence)}",
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Device Dropdown
                        DropdownButtonHideUnderline(
                          child: DropdownButton<Device>(
                            value: selectedDevice,
                            items: devices.map((device) {
                              return DropdownMenuItem<Device>(
                                value: device,
                                child: Text(
                                  "${device.name} - ${device.ip}",
                                  style: const TextStyle(
                                      color: Color(0xFFE0E0E0)),
                                ),
                              );
                            }).toList(),
                            onChanged: (Device? newVal) {
                              setState(() {
                                selectedDevice = newVal;
                              });
                            },
                            dropdownColor: const Color(0xFF121212),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // CLI Command Input and Run Button
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: commandController,
                                style:
                                    const TextStyle(color: Color(0xFFE0E0E0)),
                                decoration: const InputDecoration(
                                  labelText: "Enter CLI Command",
                                  labelStyle:
                                      TextStyle(color: Color(0xFFE0E0E0)),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Color(0xFFE0E0E0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Color(0xFFE0E0E0)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _runCommand,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(255, 79, 29, 136),
                              ),
                              child: const Text("Run",
                                  style: TextStyle(color: Color(0xFFE0E0E0))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // CLI Output Area
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: const Color(0xFF333333),
                          height: 200,
                          child: SingleChildScrollView(
                            child: Text(
                              cliOutput,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: Color(0xFFE0E0E0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}