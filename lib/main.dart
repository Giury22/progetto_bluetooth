import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Messenger',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Stato del Bluetooth
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  // Lista dei dispositivi scoperti
  List<BluetoothDiscoveryResult> _devicesList = [];
  bool _isDiscovering = false;

  // Connessione Bluetooth e stato di connessione
  BluetoothConnection? _connection;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();

    // Richiedi i permessi necessari per il Bluetooth su Android 12+
    _requestPermissions();

    // Recupera lo stato corrente del Bluetooth
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    // Ascolta le modifiche dello stato del Bluetooth
    FlutterBluetoothSerial.instance.onStateChanged().listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
      });
    });
  }

  Future<void> _requestPermissions() async {
    // Richiede i permessi necessari (Bluetooth Scan, Connect e localizzazione)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    // Facoltativo: stampa un messaggio se qualche permesso non viene concesso
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        print('Permesso non concesso: $permission');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Messenger'),
      ),
      body: Column(
        children: [
          // RIGA CON I BOTTONI
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Bottone per accendere/spegnere il Bluetooth
                ElevatedButton(
                  child: Text('On/Off Bluetooth'),
                  onPressed: () async {
                    bool enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
                    if (enabled) {
                      await FlutterBluetoothSerial.instance.requestDisable();
                    } else {
                      await FlutterBluetoothSerial.instance.requestEnable();
                    }
                  },
                ),
                // Bottone per rendere il dispositivo visibile
                ElevatedButton(
                  child: Text('Rendi visibile'),
                  onPressed: () async {
                    // Richiede di rendere il dispositivo visibile per 60 secondi
                    await FlutterBluetoothSerial.instance.requestDiscoverable(60);
                  },
                ),
                // Bottone per trovare dispositivi disponibili
                ElevatedButton(
                  child: Text('Trova dispositivi'),
                  onPressed: _isDiscovering ? null : _startDiscovery,
                ),
              ],
            ),
          ),
          // INDICATORE DI CONNESSIONE (LED)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Cerchio che funge da LED: rosso = non connesso, verde = connesso
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                SizedBox(width: 10),
                Text(_isConnected ? 'Connesso' : 'Non connesso'),
              ],
            ),
          ),
          // LISTA DEI DISPOSITIVI DISPONIBILI con il pezzo aggiornato
          Expanded(
            child: ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                BluetoothDiscoveryResult result = _devicesList[index];
                // Se il nome esiste e non è vuoto, lo mostra; altrimenti mostra "Dispositivo sconosciuto" o l'indirizzo MAC.
                String displayName = (result.device.name != null && result.device.name!.isNotEmpty)
                    ? result.device.name!
                    : "Dispositivo sconosciuto (${result.device.address})";
                
                return ListTile(
                  leading: Icon(Icons.devices),
                  title: Text(displayName),
                  subtitle: Text(result.device.address),
                  onTap: () => _connectToDevice(result.device),
                );
              },
            ),
          ),
          // Se la connessione è attiva, mostra l'interfaccia per la chat.
          if (_isConnected) _buildChatArea(),
        ],
      ),
    );
  }

  // Funzione per avviare la ricerca dei dispositivi Bluetooth
  void _startDiscovery() {
    setState(() {
      _devicesList.clear();
      _isDiscovering = true;
    });

    FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      setState(() {
        _devicesList.add(result);
      });
    }).onDone(() {
      setState(() {
        _isDiscovering = false;
      });
    });
  }

  // Funzione per connettersi a un dispositivo selezionato
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _connection = connection;
        _isConnected = true;
      });
      print('Connesso a ${device.address}');

      // Ascolta i dati in ingresso (messaggi ricevuti)
      connection.input?.listen((data) {
        String received = String.fromCharCodes(data);
        print('Messaggio ricevuto: $received');
      }).onDone(() {
        // Se la connessione si chiude
        setState(() {
          _isConnected = false;
        });
      });
    } catch (e) {
      print('Impossibile connettersi: $e');
      setState(() {
        _isConnected = false;
      });
    }
  }

  // Widget per la chat (invio e ricezione messaggi)
  Widget _buildChatArea() {
    TextEditingController _msgController = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.grey[200],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _msgController,
              decoration: InputDecoration(
                labelText: 'Inserisci messaggio...',
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () {
              if (_msgController.text.isNotEmpty && _connection != null) {
                // Invia il messaggio al dispositivo connesso
                _connection!.output.add(Uint8List.fromList(_msgController.text.codeUnits));
                _connection!.output.allSent;
                _msgController.clear();
              }
            },
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connection?.dispose();
    super.dispose();
  }
}
