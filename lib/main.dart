import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Necessario per MethodChannel ed EventChannel
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

// Definisci gli UUID per il servizio e la caratteristica BLE.
final Uuid serviceUuid = Uuid.parse("0000fff0-0000-1000-8000-00805f9b34fb");
final Uuid characteristicUuid = Uuid.parse("0000fff1-0000-1000-8000-00805f9b34fb");

/// Classe che espone il GATT server nativo tramite Platform Channel.
/// Assicurati di aver implementato anche la parte nativa (GattServerHelper.kt e la registrazione nel MainActivity.kt).
class GattServerManager {
  static const MethodChannel _channel = MethodChannel("com.example.progetto_bluetooth/gatt");

  static Future<String?> startServer() async {
    return await _channel.invokeMethod("startGattServer");
  }

  static Future<String?> stopServer() async {
    return await _channel.invokeMethod("stopGattServer");
  }

  static Future<String?> getConnectedDevice() async {
    return await _channel.invokeMethod("getConnectedDevice");
  }

  static Future<String?> sendNotification(String message, String deviceAddress) async {
    return await _channel.invokeMethod("sendNotification", {
      "message": message,
      "deviceAddress": deviceAddress,
    });
  }
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Chat',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

/// Classe per rappresentare un dispositivo scoperto (Modalità Centrale).
class DiscoveredDevice {
  final String id;
  final String name;
  DiscoveredDevice({required this.id, required this.name});
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Toggle per il ruolo: false = centrale, true = periferica.
  bool _isPeripheral = false;

  // Istanza per il ruolo centrale (client) con flutter_reactive_ble.
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  // Istanza per il ruolo periferico (advertising) con flutter_ble_peripheral.
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  // Stato della scansione (Modalità Centrale).
  List<DiscoveredDevice> _devices = [];
  bool _isScanning = false;
  DiscoveredDevice? _selectedDevice;

  // Stato della connessione BLE (Modalità Centrale).
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  QualifiedCharacteristic? _characteristic;
  bool _isConnected = false;
  String _connectionStatus = "Non connesso";
  String _receivedMessages = "";

  // Stato dell'advertising (Modalità Periferica).
  bool _isAdvertising = false;

  // Controller per l'invio dei messaggi.
  final TextEditingController _msgController = TextEditingController();

  // Variabile per memorizzare l'ultimo messaggio inviato in modalità centrale.
  String? _lastSentMessage;

  // Sottoscrizione all'EventChannel per ricevere eventi dal GATT server nativo (per periferica).
  StreamSubscription? _gattEventSubscription;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    // Se il ruolo iniziale è periferica, avvia advertising e GATT server e la sottoscrizione agli eventi.
    if (_isPeripheral) {
      _startAdvertising();
      GattServerManager.startServer().then((result) {
        print("GATT Server avviato: $result");
      });
      _startGattEventSubscription();
    }
  }

  /// Richiede i permessi necessari (localizzazione e permessi BLE).
  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        print('Permesso non concesso: $permission');
      } else {
        print('Permesso concesso: $permission');
      }
    });
  }

  /// Avvia l'advertising (Modalità Periferica).
  Future<void> _startAdvertising() async {
    final AdvertiseData advertiseData = AdvertiseData(
      includeDeviceName: true,
      manufacturerId: 0xFFFF,
      manufacturerData: Uint8List.fromList([1, 2, 3, 4]),
    );
    try {
      await _blePeripheral.start(advertiseData: advertiseData);
      setState(() {
        _isAdvertising = true;
      });
      print("Advertising avviato");
    } catch (e) {
      print("Errore nell'avvio dell'advertising: $e");
      setState(() {
        _isAdvertising = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Questo dispositivo potrebbe non supportare la modalità periferica BLE."),
        ),
      );
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await _blePeripheral.stop();
      setState(() {
        _isAdvertising = false;
      });
      print("Advertising fermato");
    } catch (e) {
      print("Errore nello stop dell'advertising: $e");
    }
  }

  /// Sottoscrizione all'EventChannel per ricevere gli eventi dal GATT server nativo.
  void _startGattEventSubscription() {
    const eventChannel = EventChannel("com.example.progetto_bluetooth/gatt_events");
    _gattEventSubscription = eventChannel.receiveBroadcastStream().listen((event) {
      setState(() {
        _receivedMessages += "Ricevuto: " + event.toString() + "\n";
      });
    }, onError: (error) {
      print("Errore nell'EventChannel: $error");
    });
  }

  void _stopGattEventSubscription() {
    _gattEventSubscription?.cancel();
    _gattEventSubscription = null;
  }

  /// Avvia la scansione dei dispositivi (Modalità Centrale).
  void _startScan() {
    setState(() {
      _devices.clear();
      _isScanning = true;
      _selectedDevice = null;
    });
    _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (!_devices.any((d) => d.id == device.id)) {
        setState(() {
          _devices.add(DiscoveredDevice(
            id: device.id,
            name: device.name.isNotEmpty ? device.name : "Dispositivo sconosciuto",
          ));
        });
      }
    }, onError: (error) {
      print("Errore durante la scansione: $error");
    });
    Future.delayed(Duration(seconds: 10), () {
      setState(() {
        _isScanning = false;
      });
    });
  }

  /// Connette al dispositivo selezionato (Modalità Centrale) e si iscrive alle notifiche.
  void _connectToDevice(DiscoveredDevice device) {
    _connectionSubscription?.cancel();
    setState(() {
      _connectionStatus = "Connessione in corso...";
    });
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: Duration(seconds: 10),
        )
        .listen((update) {
      print("Stato connessione: ${update.connectionState}");
      if (update.connectionState == DeviceConnectionState.connected) {
        setState(() {
          _isConnected = true;
          _connectionStatus = "Connesso";
          _selectedDevice = device;
        });
        _characteristic = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: characteristicUuid,
          deviceId: device.id,
        );
        _notificationSubscription =
            _ble.subscribeToCharacteristic(_characteristic!).listen((data) {
          String received = utf8.decode(data);
          // Se il messaggio ricevuto è l'eco del messaggio inviato, ignoralo.
          if (_lastSentMessage != null &&
              received.trim() == "Ricevuto: " + _lastSentMessage!) {
            print("Echo ignorato: $received");
          } else {
            setState(() {
              _receivedMessages += "Ricevuto: " + received + "\n";
            });
          }
        }, onError: (error) {
          print("Errore nelle notifiche: $error");
        });
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          _isConnected = false;
          _connectionStatus = "Disconnesso";
        });
      }
    }, onError: (error) {
      print("Errore di connessione: $error");
      setState(() {
        _connectionStatus = "Errore di connessione";
        _isConnected = false;
      });
    });
  }

  /// Invia un messaggio dal dispositivo centrale.
  Future<void> _sendMessageCentral() async {
    if (_characteristic != null && _msgController.text.isNotEmpty) {
      final message = _msgController.text;
      _lastSentMessage = message;
      try {
        await _ble.writeCharacteristicWithResponse(
          _characteristic!,
          value: utf8.encode(message),
        );
        setState(() {
          _receivedMessages += "Inviato (centrale): " + message + "\n";
        });
        print("Messaggio inviato (centrale): $message");
        _msgController.clear();
      } catch (e) {
        print("Errore nell'invio del messaggio (centrale): $e");
      }
    }
  }

  /// Invia un messaggio dal dispositivo periferico tramite il GATT server nativo.
  Future<void> _sendMessagePeripheral() async {
    final deviceAddress = await GattServerManager.getConnectedDevice();
    if (deviceAddress == null) {
      print("Nessun dispositivo connesso al GATT server.");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Nessun dispositivo connesso."),
        ),
      );
      return;
    }
    if (_msgController.text.isNotEmpty) {
      final message = _msgController.text;
      try {
        final result = await GattServerManager.sendNotification(message, deviceAddress);
        setState(() {
          _receivedMessages += "Inviato (periferica): " + message + "\n";
        });
        print("Messaggio inviato (periferica): $message, risultato: $result");
        _msgController.clear();
      } catch (e) {
        print("Errore nell'invio del messaggio (periferica): $e");
      }
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _notificationSubscription?.cancel();
    _gattEventSubscription?.cancel();
    _msgController.dispose();
    if (_isPeripheral) {
      GattServerManager.stopServer().then((result) {
        print("GATT Server fermato: $result");
      });
      _stopAdvertising();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("BLE Chat"),
        actions: [
          Row(
            children: [
              Text(_isPeripheral ? "Periferica" : "Centrale"),
              Switch(
                value: _isPeripheral,
                onChanged: (value) {
                  setState(() {
                    _isPeripheral = value;
                    // Reset degli stati quando si cambia ruolo.
                    _devices.clear();
                    _selectedDevice = null;
                    _isConnected = false;
                    _connectionStatus = "Non connesso";
                    _receivedMessages = "";
                    _stopGattEventSubscription();
                    if (_isPeripheral) {
                      _startAdvertising();
                      GattServerManager.startServer().then((result) {
                        print("GATT Server avviato: $result");
                      });
                      _startGattEventSubscription();
                    } else {
                      _stopAdvertising();
                      GattServerManager.stopServer().then((result) {
                        print("GATT Server fermato: $result");
                      });
                    }
                  });
                },
              ),
              SizedBox(width: 8),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Stato della connessione
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("Stato: $_connectionStatus"),
            ),
            // Sezione per la modalità periferica.
            Card(
              margin: EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text("Modalità Periferica (Advertising)"),
                    SizedBox(height: 8),
                    ElevatedButton(
                      child: Text(_isAdvertising ? "Ferma Advertising" : "Avvia Advertising"),
                      onPressed: () {
                        if (_isAdvertising) {
                          _stopAdvertising();
                        } else {
                          _startAdvertising();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Sezione per la modalità centrale.
            Card(
              margin: EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text("Modalità Centrale (Scansione e Connessione)"),
                    SizedBox(height: 8),
                    ElevatedButton(
                      child: Text(_isScanning ? "Scansione in corso..." : "Trova dispositivi"),
                      onPressed: _isScanning ? null : _startScan,
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 200,
                      child: ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return ListTile(
                            title: Text(device.name),
                            subtitle: Text(device.id),
                            trailing: (_selectedDevice != null && _selectedDevice!.id == device.id)
                                ? Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () {
                              setState(() {
                                if (_selectedDevice != null && _selectedDevice!.id == device.id) {
                                  _selectedDevice = null;
                                } else {
                                  _selectedDevice = device;
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    if (_selectedDevice != null && !_isConnected)
                      ElevatedButton(
                        child: Text('Connetti a "${_selectedDevice!.name}"'),
                        onPressed: () => _connectToDevice(_selectedDevice!),
                      ),
                  ],
                ),
              ),
            ),
            // Sezione Chat unificata.
            Card(
              margin: EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _msgController,
                      decoration: InputDecoration(labelText: "Inserisci messaggio"),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      child: Text("Invia messaggio"),
                      onPressed: () {
                        // Se il dispositivo è connesso in modalità centrale, invia tramite quella; altrimenti, utilizza la modalità periferica.
                        if (_isConnected) {
                          _sendMessageCentral();
                        } else {
                          _sendMessagePeripheral();
                        }
                      },
                    ),
                    SizedBox(height: 8),
                    Text("Chat:\n$_receivedMessages"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
