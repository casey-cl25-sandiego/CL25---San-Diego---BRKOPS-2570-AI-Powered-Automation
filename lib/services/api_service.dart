import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../my_dart_app.dart';
import '../config.dart';

class ApiService {
  static const String baseUrl = "https://198.18.129.100";

  /// Authenticates using credentials from config.dart.
  /// If useAES is true, includes a placeholder for AES support.
  static Future<String> authenticate() async {
    final String authEndpoint = "$baseUrl/dna/system/api/v1/auth/token";
    String credentials = base64Encode(utf8.encode("$username:$password"));
    Map<String, String> headers = {
      'Authorization': "Basic $credentials",
      'Content-Type': "application/json",
    };

    // Placeholder for AES support if enabled.
    if (useAES) {
      headers['Authorization'] =
          "CSCO-AES-256 credentials=$credentials"; // AES placeholder
    }

    final response = await http.post(Uri.parse(authEndpoint), headers: headers);
    if (response.statusCode == 200) {
      Map<String, dynamic> jsonResponse = json.decode(response.body);
      if (jsonResponse.containsKey("Token")) {
        return jsonResponse["Token"];
      } else {
        throw Exception("Token not found in authentication response.");
      }
    } else if (response.statusCode == 401) {
      throw Exception("Invalid credentials");
    } else {
      throw Exception(
          "Authentication failed with status: ${response.statusCode}");
    }
  }

  /// Retrieves the list of network devices.
  static Future<List<Device>> getDevices(String token) async {
    final String devicesEndpoint = "$baseUrl/dna/intent/api/v1/network-device";
    final response = await http.get(Uri.parse(devicesEndpoint), headers: {
      'X-Auth-Token': token,
      'Content-Type': "application/json",
    });

    if (response.statusCode == 200) {
      List<Device> deviceList = [];
      Map<String, dynamic> jsonResponse = json.decode(response.body);
      if (jsonResponse.containsKey("response")) {
        for (var item in jsonResponse["response"]) {
          String? id = item["uuid"] ?? item["id"];
          String? name = item["hostname"];
          String? ip = item["managementIpAddress"];
          if (id != null && name != null && ip != null) {
            deviceList.add(Device(uuid: id, name: name, ip: ip));
          } else {
            print("Warning: Device identifier missing for item: $item");
          }
        }
      }
      return deviceList;
    } else {
      throw Exception(
          "Failed to retrieve devices. Status: ${response.statusCode}");
    }
  }

  /// Retrieves the list of issues within the last 24 hours.
  static Future<List<Issue>> getIssues(String token) async {
    final int endTime = DateTime.now().millisecondsSinceEpoch;
    final int startTime =
        DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final String issuesEndpoint =
        "$baseUrl/dna/intent/api/v1/issues?startTime=$startTime&endTime=$endTime";

    final response = await http.get(Uri.parse(issuesEndpoint), headers: {
      'X-Auth-Token': token,
      'Content-Type': "application/json",
    });

    if (response.statusCode == 200) {
      List<Issue> issuesList = [];
      Map<String, dynamic> jsonResponse = json.decode(response.body);
      if (jsonResponse.containsKey("response")) {
        for (var item in jsonResponse["response"]) {
          String priority = item["priority"]?.toString() ?? "Unknown";
          String description = item["name"] ?? "";
          // Extract affected device name via regex. Adjust pattern as needed.
          RegExp regex = RegExp(r"Device\s*:\s*(\S+)");
          Match? match = regex.firstMatch(description);
          String affectedDevice = match != null ? match.group(1)! : "Unknown";
          int lastOccurrenceMillis = item["lastOccurrenceTime"] ?? 0;
          DateTime lastOccurrence =
              DateTime.fromMillisecondsSinceEpoch(lastOccurrenceMillis);
          issuesList.add(Issue(
            priority: priority,
            description: description,
            affectedDevice: affectedDevice,
            lastOccurrence: lastOccurrence,
          ));
        }
      }
      return issuesList;
    } else {
      throw Exception(
          "Failed to retrieve issues. Status: ${response.statusCode}");
    }
  }

  /// Runs the CLI command on the given device and returns the CLI output.
  static Future<String> runCommand(
      String token, String deviceUuid, String command) async {
    final String commandEndpoint =
        "$baseUrl/dna/intent/api/v1/network-device-poller/cli/read-request";
    Map<String, dynamic> payload = {
      "timeout": 300,
      "description": "Execute CLI command",
      "name": "runCLICommand",
      "commands": [command],
      "deviceUuids": [deviceUuid],
    };

    final response = await http.post(Uri.parse(commandEndpoint),
        headers: {
          'X-Auth-Token': token,
          'Content-Type': "application/json",
        },
        body: json.encode(payload));

    if ([200, 201, 202].contains(response.statusCode)) {
      Map<String, dynamic> jsonResponse = json.decode(response.body);
      if (jsonResponse.containsKey("response") &&
          jsonResponse["response"]["taskId"] != null) {
        String taskId = jsonResponse["response"]["taskId"];
        String? fileId = await _pollTaskResult(token, taskId);
        if (fileId != null) {
          String cliOutput = await _getFileContents(token, fileId, command);
          return cliOutput;
        } else {
          throw Exception("CLI output file not generated.");
        }
      } else {
        throw Exception("Task ID not found in response.");
      }
    } else {
      throw Exception(
          "Failed to run command. Status: ${response.statusCode}");
    }
  }

  /// Polls the task API until a fileId is available (up to 20 attempts at 2-second intervals).
static Future<String?> _pollTaskResult(String token, String taskId) async {
  final String taskEndpoint = "$baseUrl/dna/intent/api/v1/task/$taskId";
  for (int attempt = 0; attempt < 20; attempt++) {
    final response = await http.get(Uri.parse(taskEndpoint), headers: {
      'X-Auth-Token': token,
      'Content-Type': "application/json",
    });
    print("Polling attempt $attempt, status code: ${response.statusCode}");
    print("Task response body: ${response.body}");
    if (response.statusCode == 200) {
      Map<String, dynamic> jsonResponse = json.decode(response.body);
      // Get the inner 'response' field.
      if (jsonResponse.containsKey("response") && jsonResponse["response"] is Map) {
        Map<String, dynamic> innerResponse = jsonResponse["response"];
        if (innerResponse.containsKey("progress")) {
          final rawProgress = innerResponse["progress"];
          print("Raw progress on attempt $attempt: $rawProgress");
        
          dynamic progressData;
          try {
            progressData = json.decode(rawProgress);
            print("Decoded progressData: $progressData");
          } catch (e) {
            progressData = rawProgress;
            print("ProgressData as raw string: $progressData");
          }
        
          // If progressData is a Map, try to get fileId directly.
          if (progressData is Map && progressData["fileId"] != null) {
            print("Found fileId in progressData Map: ${progressData["fileId"]}");
            return progressData["fileId"].toString();
          }
        
          // Else if progressData is a String, attempt regex extraction.
          if (progressData is String) {
            RegExp fileIdRegex = RegExp(r'"fileId"\s*:\s*"([^"]+)"');
            Match? match = fileIdRegex.firstMatch(progressData);
            if (match != null) {
              print("Found fileId via regex: ${match.group(1)}");
              return match.group(1);
            } else {
              print("Regex did not match fileId on attempt $attempt");
            }
          }
        } else {
          print("No 'progress' field found in inner response on attempt $attempt.");
        }
      } else {
        print("No 'response' field found on attempt $attempt.");
      }
    } else {
      print("Non-success status code ${response.statusCode} on attempt $attempt.");
    }
    await Future.delayed(const Duration(seconds: 2));
  }
  print("Exiting _pollTaskResult without finding fileId after 20 attempts.");
  return null;
}

static Future<String> _getFileContents(
    String token, String fileId, String command) async {
  final String fileEndpoint = "$baseUrl/dna/intent/api/v1/file/$fileId";
  final response = await http.get(Uri.parse(fileEndpoint), headers: {
    'X-Auth-Token': token,
    'Content-Type': "application/json",
  });
  print("File endpoint response status: ${response.statusCode}");
  print("File endpoint response body: ${response.body}");
  if (response.statusCode == 200) {
    List<dynamic> fileResponse = json.decode(response.body);
    if (fileResponse.isNotEmpty &&
        fileResponse[0]["commandResponses"] != null) {
      Map<String, dynamic> commandResponses =
          fileResponse[0]["commandResponses"];
      if (commandResponses.containsKey("SUCCESS")) {
        print("CLI output found: ${commandResponses["SUCCESS"]}");
        return commandResponses["SUCCESS"].toString();
      }
    }
    throw Exception("CLI output not found in file response.");
  } else {
    throw Exception(
        "Failed to retrieve file contents. Status: ${response.statusCode}");
  }
}
}