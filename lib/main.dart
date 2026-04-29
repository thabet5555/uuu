import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(AttackDetectorApp());

class AttackDetectorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'WiFi Attack Detector',
    theme: ThemeData.dark().copyWith(
      primaryColor: Colors.cyan,
      colorScheme: ColorScheme.dark(primary: Colors.cyan),
    ),
    home: HomePage(),
  );
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // BLE objects
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? txChar; // Notify from device
  BluetoothCharacteristic? rxChar; // Write to device
  StreamSubscription<dynamic>? txSubscription;
  String deviceName = "ESP32_AttackDetector";

  // Service and characteristic UUIDs
  final String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String rxUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  final String txUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  // State variables from device
  bool isMonitoring = false;
  String selectedNetwork = "";
  int monitorChannel = 0;
  int currentPacketRate = 0;
  List<String> scanResults = [];
  Map<String, int> thresholds = {
    'deauth': 8, 'beacon': 30, 'probe': 25, 'mac': 8,
    'arp': 8, 'frag': 12, 'rts': 10, 'arpscan': 15,
  };
  List<String> attackHistory = [];
  String lastAlert = "";

  // UI
  int currentTab = 0;
  List<String> tabs = ["Scan", "Monitor", "Settings", "History"];

  @override
  void dispose() {
    txSubscription?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
  }

  // ===================== BLE Functions =====================
  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      connectedDevice = device; // يظهر التبويبات فورًا
    });
    try {
      await device.connect();
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString().toUpperCase() == serviceUuid.toUpperCase()) {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString().toUpperCase() == txUuid.toUpperCase()) {
              txChar = c;
              await c.setNotifyValue(true);
              txSubscription = c.value.listen((value) {
                String response = String.fromCharCodes(value);
                processResponse(response);
              });
            } else if (c.uuid.toString().toUpperCase() == rxUuid.toUpperCase()) {
              rxChar = c;
            }
          }
        }
      }
      setState(() {});
      sendCommand("status");
    } catch (e) {
      // فشل الاتصال – إعادة التعيين
      connectedDevice = null;
      txChar = null;
      rxChar = null;
      setState(() {});
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Connection Error"),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))],
        ),
      );
    }
  }

  Future<void> sendCommand(String cmd) async {
    if (rxChar == null) return;
    await rxChar!.write(cmd.codeUnits, withoutResponse: true);
    debugPrint("Sent: $cmd");
  }

  void processResponse(String response) {
    setState(() {
      if (response.startsWith("OK: Monitoring started")) {
        isMonitoring = true;
      } else if (response.startsWith("OK: Monitoring stopped") || response.contains("Returned to main menu")) {
        isMonitoring = false;
      } else if (response.startsWith("OK: Selected")) {
        RegExp reg = RegExp(r"OK: Selected (.+) \(Ch (\d+)\)");
        Match? match = reg.firstMatch(response);
        if (match != null) {
          selectedNetwork = match.group(1)!;
          monitorChannel = int.parse(match.group(2)!);
        }
      } else if (response.startsWith("Networks found:")) {
        scanResults = response.split("\n").where((line) => line.contains(":")).toList();
      } else if (response.startsWith("Status:")) {
        isMonitoring = response.contains("Monitoring: YES");
        RegExp netReg = RegExp(r"Network: (.+)");
        RegExp chReg = RegExp(r"Channel: (\d+)");
        Match? netMatch = netReg.firstMatch(response);
        Match? chMatch = chReg.firstMatch(response);
        if (netMatch != null) selectedNetwork = netMatch.group(1)!.trim();
        if (chMatch != null) monitorChannel = int.parse(chMatch.group(1)!);
        if (selectedNetwork == "none") selectedNetwork = "";
      } else if (response.contains("--- Last")) {
        attackHistory = response.split("\n").where((line) => line.contains(" on ")).toList();
      }
      // يمكن إضافة معالجة لردود أخرى مثل تعديل العتبات
    });
  }

  // ===================== UI Body =====================
  Widget buildBody() {
    if (connectedDevice == null || rxChar == null) {
      return ScanDeviceScreen(
        onDeviceSelected: connectToDevice,
        targetName: deviceName,
      );
    }
    // بعد الاتصال وتعيين الخدمات، نعرض التبويبات
    switch (currentTab) {
      case 0:
        return WifiScanScreen(
          sendCommand: sendCommand,
          scanResults: scanResults,
          selectedNetwork: selectedNetwork,
        );
      case 1:
        return MonitorScreen(
          sendCommand: sendCommand,
          isMonitoring: isMonitoring,
          selectedNetwork: selectedNetwork,
          monitorChannel: monitorChannel,
          packetRate: currentPacketRate,
        );
      case 2:
        return SettingsScreen(
          sendCommand: sendCommand,
          thresholds: thresholds,
        );
      case 3:
        return HistoryScreen(
          sendCommand: sendCommand,
          history: attackHistory,
        );
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(connectedDevice != null ? "Connected: $deviceName" : "WiFi Attack Detector"),
        actions: [
          if (connectedDevice != null)
            IconButton(
              icon: Icon(Icons.bluetooth_disabled),
              onPressed: () {
                connectedDevice?.disconnect();
                setState(() {
                  connectedDevice = null;
                  txChar = null;
                  rxChar = null;
                });
              },
            ),
        ],
      ),
      body: buildBody(),
      bottomNavigationBar: connectedDevice != null && rxChar != null
          ? BottomNavigationBar(
        currentIndex: currentTab,
        onTap: (index) {
          setState(() => currentTab = index);
          if (index == 2) sendCommand("settings");
          if (index == 3) sendCommand("history");
          if (index == 1) sendCommand("status");
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.wifi), label: "Scan"),
          BottomNavigationBarItem(icon: Icon(Icons.monitor), label: "Monitor"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "History"),
        ],
      )
          : null,
    );
  }
}

// ===================== شاشة الاتصال =====================
class ScanDeviceScreen extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceSelected;
  final String targetName;
  ScanDeviceScreen({required this.onDeviceSelected, required this.targetName});

  @override
  State<ScanDeviceScreen> createState() => _ScanDeviceScreenState();
}

class _ScanDeviceScreenState extends State<ScanDeviceScreen> {
  List<ScanResult> devices = [];
  bool scanning = false;
  bool connecting = false;

  void startScan() {
    setState(() {
      scanning = true;
      devices.clear();
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        devices = results;
      });
    });
    Timer(Duration(seconds: 10), () {
      FlutterBluePlus.stopScan();
      setState(() => scanning = false);
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => connecting = true);
    try {
      await device.connect();
      widget.onDeviceSelected(device); // يستدعي connectToDevice في HomePage
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Connection failed"),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))],
        ),
      );
    } finally {
      setState(() => connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: scanning ? null : startScan,
          icon: Icon(Icons.bluetooth_searching),
          label: Text(scanning ? "Scanning..." : "Scan for Devices"),
        ),
        if (connecting) LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: devices.length,
            itemBuilder: (context, i) {
              ScanResult result = devices[i];
              bool isTarget = result.device.name == widget.targetName;
              return ListTile(
                title: Text(result.device.name.isNotEmpty ? result.device.name : "Unknown",
                    style: TextStyle(fontSize: 16)),
                subtitle: Text(result.device.id.toString()),
                trailing: isTarget ? Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () => _connectToDevice(result.device),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===================== شاشة مسح الشبكات =====================
class WifiScanScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final List<String> scanResults;
  final String selectedNetwork;

  WifiScanScreen({
    required this.sendCommand,
    required this.scanResults,
    required this.selectedNetwork,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => sendCommand("scan"),
          icon: Icon(Icons.wifi_find),
          label: Text("Scan Networks"),
        ),
        if (selectedNetwork.isNotEmpty)
          Padding(
            padding: EdgeInsets.all(8),
            child: Text("Selected: $selectedNetwork", style: TextStyle(color: Colors.cyan)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: scanResults.length,
            itemBuilder: (context, i) {
              String line = scanResults[i];
              return ListTile(
                leading: Icon(Icons.wifi),
                title: Text(line),
                onTap: () {
                  RegExp reg = RegExp(r'^(\d+):');
                  Match? match = reg.firstMatch(line);
                  if (match != null) {
                    String num = match.group(1)!;
                    sendCommand("select $num");
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ===================== شاشة المراقبة =====================
class MonitorScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final bool isMonitoring;
  final String selectedNetwork;
  final int monitorChannel;
  final int packetRate;

  MonitorScreen({
    required this.sendCommand,
    required this.isMonitoring,
    required this.selectedNetwork,
    required this.monitorChannel,
    required this.packetRate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Text("Network: ${selectedNetwork.isNotEmpty ? selectedNetwork : "None"}",
              style: TextStyle(fontSize: 18)),
          Text("Channel: $monitorChannel", style: TextStyle(fontSize: 16)),
          SizedBox(height: 20),
          Icon(
            isMonitoring ? Icons.wifi_tethering : Icons.wifi_off,
            size: 80,
            color: isMonitoring ? Colors.red : Colors.grey,
          ),
          Text(isMonitoring ? "Monitoring Active" : "Idle", style: TextStyle(fontSize: 20)),
          SizedBox(height: 10),
          Text("Packet Rate: $packetRate pkt/s"),
          SizedBox(height: 30),
          if (!isMonitoring)
            ElevatedButton.icon(
              onPressed: selectedNetwork.isEmpty ? null : () => sendCommand("monitor"),
              icon: Icon(Icons.play_arrow),
              label: Text("Start Monitoring"),
            )
          else
            ElevatedButton.icon(
              onPressed: () => sendCommand("stop"),
              icon: Icon(Icons.stop),
              label: Text("Stop Monitoring"),
            ),
        ],
      ),
    );
  }
}

// ===================== شاشة الإعدادات =====================
class SettingsScreen extends StatefulWidget {
  final Function(String) sendCommand;
  final Map<String, int> thresholds;

  SettingsScreen({required this.sendCommand, required this.thresholds});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, int> localThresholds;
  Map<String, String> labels = {
    'deauth': 'Deauth Flood',
    'beacon': 'Beacon Flood',
    'probe': 'Probe Flood',
    'mac': 'MAC Spoofing',
    'arp': 'ARP Spoofing',
    'frag': 'Fragmentation',
    'rts': 'RTS Flood',
    'arpscan': 'ARP Scan',
  };

  @override
  void initState() {
    super.initState();
    localThresholds = Map.from(widget.thresholds);
    widget.sendCommand("settings");
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: localThresholds.length,
      itemBuilder: (context, i) {
        String key = localThresholds.keys.elementAt(i);
        int value = localThresholds[key]!;
        return ListTile(
          title: Text(labels[key] ?? key),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.remove),
                onPressed: () {
                  setState(() => localThresholds[key] = (value - 1).clamp(0, 100));
                  widget.sendCommand("threshold $key ${localThresholds[key]}");
                },
              ),
              Text("$value", style: TextStyle(fontSize: 18)),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () {
                  setState(() => localThresholds[key] = (value + 1).clamp(0, 100));
                  widget.sendCommand("threshold $key ${localThresholds[key]}");
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ===================== شاشة التقارير =====================
class HistoryScreen extends StatelessWidget {
  final Function(String) sendCommand;
  final List<String> history;

  HistoryScreen({required this.sendCommand, required this.history});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => sendCommand("history"),
          icon: Icon(Icons.refresh),
          label: Text("Refresh History"),
        ),
        Expanded(
          child: history.isEmpty
              ? Center(child: Text("No attacks recorded"))
              : ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, i) => ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text(history[i]),
            ),
          ),
        ),
      ],
    );
  }
}