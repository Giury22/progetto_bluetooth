package com.example.progetto_bluetooth

import android.bluetooth.*
import android.content.Context
import android.util.Log
import java.util.*

class GattServerHelper(private val context: Context) {

    private var bluetoothGattServer: BluetoothGattServer? = null
    private var connectedDevice: BluetoothDevice? = null

    // Definisci gli UUID per il servizio e la caratteristica
    private val SERVICE_UUID: UUID = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
    private val CHARACTERISTIC_UUID: UUID = UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")

    // Callback del GATT server
    private val gattServerCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            super.onConnectionStateChange(device, status, newState)
            Log.i("GattServerHelper", "onConnectionStateChange: ${device.address} newState: $newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (device == connectedDevice) {
                    connectedDevice = null
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            super.onCharacteristicReadRequest(device, requestId, offset, characteristic)
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
                // In risposta a una richiesta di lettura, inviamo il valore attuale della caratteristica
                val value = characteristic.value ?: "Nessun messaggio".toByteArray()
                bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            } else {
                bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            super.onCharacteristicWriteRequest(device, requestId, characteristic, preparedWrite, responseNeeded, offset, value)
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
                // Leggiamo il messaggio inviato e creiamo un echo
                val receivedMessage = String(value, Charsets.UTF_8)
                Log.i("GattServerHelper", "Messaggio ricevuto da ${device.address}: $receivedMessage")
                val echoMessage = "Ricevuto: $receivedMessage"
                characteristic.value = echoMessage.toByteArray(Charsets.UTF_8)
                // Inviaamo la risposta se richiesta
                if (responseNeeded) {
                    bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, characteristic.value)
                }
                // Inviamo una notifica per aggiornare il client
                notifyCharacteristicChanged(characteristic, device)
            } else {
                if (responseNeeded) {
                    bluetoothGattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
                }
            }
        }

        private fun notifyCharacteristicChanged(characteristic: BluetoothGattCharacteristic, device: BluetoothDevice) {
            bluetoothGattServer?.notifyCharacteristicChanged(device, characteristic, false)
        }
    }

    // Avvia il GATT server e aggiunge il servizio con la caratteristica.
    fun startServer(): Boolean {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothGattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        if (bluetoothGattServer == null) {
            Log.e("GattServerHelper", "Impossibile aprire il GATT server")
            return false
        }
        val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        service.addCharacteristic(characteristic)
        val added = bluetoothGattServer?.addService(service) ?: false
        Log.i("GattServerHelper", "Servizio aggiunto: $added")
        return added
    }

    // Ferma il GATT server.
    fun stopServer() {
        bluetoothGattServer?.close()
        bluetoothGattServer = null
        connectedDevice = null
        Log.i("GattServerHelper", "GATT server fermato")
    }

    // Restituisce l'indirizzo del dispositivo connesso (se presente).
    fun getConnectedDevice(): String? {
        return connectedDevice?.address
    }

    // Invia una notifica (scrive il messaggio nella caratteristica e notifica il client).
    fun sendNotification(message: String): Boolean {
        if (bluetoothGattServer == null || connectedDevice == null) return false
        val service = bluetoothGattServer?.getService(SERVICE_UUID) ?: return false
        val characteristic = service.getCharacteristic(CHARACTERISTIC_UUID) ?: return false
        characteristic.value = message.toByteArray(Charsets.UTF_8)
        val notified = bluetoothGattServer?.notifyCharacteristicChanged(connectedDevice, characteristic, false) ?: false
        Log.i("GattServerHelper", "Notifica inviata: $notified")
        return notified
    }
}
