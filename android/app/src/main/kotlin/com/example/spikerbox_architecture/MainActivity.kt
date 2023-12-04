package com.example.spikerbox_architecture

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
}


// package com.example.spikerbox_architecture

// import android.app.PendingIntent
// import android.content.BroadcastReceiver
// import android.content.Context
// import android.content.Intent
// import android.content.IntentFilter
// import android.hardware.usb.UsbDevice
// import android.hardware.usb.UsbDeviceConnection
// import android.hardware.usb.UsbManager
// import android.util.Log
// import io.flutter.embedding.android.FlutterActivity
// import io.flutter.embedding.engine.FlutterEngine
// import io.flutter.plugin.common.EventChannel
// import io.flutter.plugin.common.MethodChannel
// import kotlin.experimental.or


// private const val ACTION_USB_PERMISSION = "com.example.spikerbox_architecture.USB_PERMISSION"

// class MainActivity : FlutterActivity() {
//     var device: UsbDevice? = null
//     var activity: MainActivity? = null
//     lateinit var permissionIntent: PendingIntent
//     lateinit var manager: UsbManager

//     var connection: UsbDeviceConnection? = null
//     var isReading = false

//     var mEvents: EventChannel.EventSink? = null
//     var mEvents2: EventChannel.EventSink? = null

//     override fun onDestroy() {
//         val count = device?.interfaceCount
//         isReading = false
//         if ((count ?: 0) > 0) {
//             device?.getInterface(0).apply {

//                 connection?.releaseInterface(this)
//                 connection?.close()
//                 connection = null
//             }
//         }
//         super.onDestroy()
//     }

//     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//         super.configureFlutterEngine(flutterEngine)
//         activity = this

//         EventChannel(
//             flutterEngine.dartExecutor.binaryMessenger,
//             "listenUSBState"
//         ).setStreamHandler(object : EventChannel.StreamHandler {
//             override fun onCancel(arguments: Any?) {

//             }

//             override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
//                 mEvents2 = events
//                 manager = getSystemService(Context.USB_SERVICE) as UsbManager
//                 val deviceList = manager.deviceList

//                 permissionIntent =
//                     PendingIntent.getBroadcast(activity, 0, Intent(ACTION_USB_PERMISSION), PendingIntent.FLAG_IMMUTABLE)
//                 val filter = IntentFilter(ACTION_USB_PERMISSION)
//                 filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
//                 filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
//                 registerReceiver(usbReceiver, filter)
//                 val keys = deviceList.keys
//                 if (keys.size > 0) {
//                     device = deviceList[keys.first()]
//                     Log.d("requesting permission : ", "for USB")
//                     manager.requestPermission(device, permissionIntent)
//                 }
//             }
//         })
//     }

//     private val usbReceiver = object : BroadcastReceiver() {

//         override fun onReceive(context: Context, intent: Intent) {
//             val forceClaim = true
//             if (ACTION_USB_PERMISSION == intent.action || intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
//                 if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
//                     device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
//                     if (device == null) {
//                         return
//                     }
//                     if (!manager.hasPermission(device)) {
//                         manager.requestPermission(device, permissionIntent)
//                         return
//                     }

//                 }
//                 synchronized(this) {
//                     device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)

//                     if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
//                         mEvents2?.success("ATTACHED")
//                     } else {
//                         mEvents2?.success("PERMISSION_DENIED")
//                         Log.d("UsbReceiver Broadcast", "permission denied for device $device")
//                     }
//                 }
//             } else {

//                 if (intent.action == UsbManager.ACTION_USB_DEVICE_DETACHED) {

//                     val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
//                     device?.apply {
//                         device.getInterface(0).also { intr ->
//                             isReading = false
//                             try {
//                                 Thread.sleep(50)
//                             } catch (e: InterruptedException) {
//                             }
//                             connection?.releaseInterface(intr)
//                         }
//                     }
//                     mEvents2?.success("DETACHED");

//                 }
//             }
//         }
//     }
// }