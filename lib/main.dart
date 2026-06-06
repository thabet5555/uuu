import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const AttackDetectorApp());

class AttackDetectorApp extends StatelessWidget {
  const AttackDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WiFi Attack Detector',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Colors.cyan),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? txChar;
  BluetoothCharacteristic? rxChar;

  StreamSubscription<List<ScanResult>>? scanSub;
  StreamSubscription<List<int>>? txSub;

  String deviceName = "ESP32_AttackDetector";

  final String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String rxUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  final String txUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  bool isMonitoring = false;
  String selectedNetwork = "";
  int monitorChannel = 0;
  int currentTab = 0;

  List<String> scanResults = [];
  List<String> attackHistory = [];

  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() => connectedDevice = device);

    try {
      await device.connect(autoConnect: false);

      final services = await device.discoverServices();

      for (var s in services) {
        if (s.uuid.toString().toUpperCase() == serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toUpperCase() == txUuid) {
              txChar = c;
              await c.setNotifyValue(true);

              txSub = c.onValueReceived.listen((value) {
                final response = String.fromCharCodes(value);
                processResponse(response);
              });
            }

            if (c.uuid.toString().toUpperCase() == rxUuid) {
              rxChar = c;
            }
          }
        }
      }

      setState(() {});
      sendCommand("status");
    } catch (e) {
      setState(() {
        connectedDevice = null;
        txChar = null;
        rxChar = null;
      });
    }
  }

  Future<void> sendCommand(String cmd) async {
    if (rxChar == null) return;
    await rxChar!.write(cmd.codeUnits, withoutResponse: true);
  }

  void processResponse(String r) {
    setState(() {
      if (r.contains("Monitoring started")) isMonitoring = true;
      if (r.contains("Monitoring stopped")) isMonitoring = false;

      if (r.startsWith("OK: Selected")) {
        final reg = RegExp(r"OK: Selected (.+) \(Ch (\d+)\)");
        final m = reg.firstMatch(r);
        if (m != null) {
          selectedNetwork = m.group(1)!;
          monitorChannel = int.parse(m.group(2)!);
        }
      }

      if (r.startsWith("Networks found")) {
        scanResults = r.split("\n");
      }

      if (r.contains(" on ")) {
        attackHistory.add(r);
      }
    });
  }

  Widget buildBody() {
    if (connectedDevice == null || rxChar == null) {
      return ScanDeviceScreen(
        onDeviceSelected: connectToDevice,
        targetName: deviceName,
      );
    }

    if (currentTab == 0) {
      return WifiScanScreen(
        sendCommand: sendCommand,
        scanResults: scanResults,
        selectedNetwork: selectedNetwork,
      );
    }

    if (currentTab == 1) {
      return MonitorScreen(
        sendCommand: sendCommand,
        isMonitoring: isMonitoring,
        selectedNetwork: selectedNetwork,
        monitorChannel: monitorChannel,
        packetRate: 0,
      );
    }

    if (currentTab == 2) {
      return SettingsScreen(
        sendCommand: sendCommand,
        thresholds: const {},
      );
    }

    return HistoryScreen(
      sendCommand: sendCommand,
      history: attackHistory,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
      ),
      body: buildBody(),
      bottomNavigationBar: connectedDevice == null
          ? null
          : BottomNavigationBar(
              currentIndex: currentTab,
              onTap: (i) => setState(() => currentTab = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.wifi), label: "Scan"),
                BottomNavigationBarItem(icon: Icon(Icons.monitor), label: "Monitor"),
                BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
                BottomNavigationBarItem(icon: Icon(Icons.history), label: "History"),
              ],
            ),
    );
  }
}

class ScanDeviceScreen extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceSelected;
  final String targetName;

  const ScanDeviceScreen({
    super.key,
    required this.onDeviceSelected,
    required this.targetName,
  });

  @override
  State<ScanDeviceScreen> createState() => _ScanDeviceScreenState();
}

class _ScanDeviceScreenState extends State<ScanDeviceScreen> {
  List<ScanResult> devices = [];
  bool scanning = false;

  void startScan() {
    setState(() => scanning = true);

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) {
      setState(() => devices = results);
    });

    Future.delayed(const Duration(seconds: 10), () {
      FlutterBluePlus.stopScan();
      setState(() => scanning = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: scanning ? null : startScan,
          child: Text(scanning ? "Scanning..." : "Scan"),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: devices.length,
            itemBuilder: (c, i) {
              final d = devices[i].device;

              return ListTile(
                title: Text(d.name.isEmpty ? "Unknown" : d.name),
                subtitle: Text(d.id.toString()),
                onTap: () => widget.onDeviceSelected(d),
              );
            },
          ),
        ),
      ],
    );
  }
}

class WifiScanScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final List<String> scanResults;
  final String selectedNetwork;

  const WifiScanScreen({
    super.key,
    required this.sendCommand,
    required this.scanResults,
    required this.selectedNetwork,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => sendCommand("scan"),
          child: const Text("Scan Networks"),
        ),
        Text(selectedNetwork),
        Expanded(
          child: ListView(
            children: scanResults.map((e) => ListTile(title: Text(e))).toList(),
          ),
        )
      ],
    );
  }
}

class MonitorScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final bool isMonitoring;
  final String selectedNetwork;
  final int monitorChannel;
  final int packetRate;

  const MonitorScreen({
    super.key,
    required this.sendCommand,
    required this.isMonitoring,
    required this.selectedNetwork,
    required this.monitorChannel,
    required this.packetRate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(selectedNetwork),
        Text("Channel: $monitorChannel"),
        ElevatedButton(
          onPressed: () => sendCommand(isMonitoring ? "stop" : "monitor"),
          child: Text(isMonitoring ? "Stop" : "Start"),
        )
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final Map<String, int> thresholds;

  const SettingsScreen({
    super.key,
    required this.sendCommand,
    required this.thresholds,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Settings"));
  }
}

class HistoryScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final List<String> history;

  const HistoryScreen({
    super.key,
    required this.sendCommand,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: history.map((e) => ListTile(title: Text(e))).toList(),
    );
  }
}
