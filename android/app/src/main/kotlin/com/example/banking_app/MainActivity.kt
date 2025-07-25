package com.alexosuya.bankal

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() {
    // ...
}
//import android.content.BroadcastReceiver
//import android.content.Context
//import android.content.Intent
//import android.os.Bundle
//import android.telephony.SmsMessage
//import android.util.Log
//
//class SMSReceiver : BroadcastReceiver() {
//    override fun onReceive(context: Context, intent: Intent) {
//        val bundle: Bundle? = intent.extras
//        if (bundle != null) {
//            val pdus = bundle["pdus"] as Array<*>?
//            pdus?.forEach {
//                val format = bundle.getString("format")
//                val sms = SmsMessage.createFromPdu(it as ByteArray, format)
//                val sender = sms.originatingAddress
//                val body = sms.messageBody
//
//                Log.d("SMSReceiver", "SMS from $sender: $body")
//
//                // TODO: You can save this to SharedPreferences or call a Flutter method channel if app is running
//            }
//        }
//    }
//}
