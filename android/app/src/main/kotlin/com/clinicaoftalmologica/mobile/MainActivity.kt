package com.clinicaoftalmologica.mobile

import android.os.Build
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import android.content.Intent
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// flutter_stripe requiere FlutterFragmentActivity: el PaymentSheet de Stripe
// usa el Support Fragment Manager de Android.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "clinica_oftalmologica_mobile/cu41_voice",
        ).setMethodCallHandler { call, result ->
            if (call.method != "diagnoseRecognition") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val services = packageManager.queryIntentServices(
                    Intent(RecognitionService.SERVICE_INTERFACE), 0,
                )
                val general = SpeechRecognizer.isRecognitionAvailable(applicationContext)
                val onDevice = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(applicationContext)
                val selected = android.provider.Settings.Secure.getString(
                    contentResolver,
                    "voice_recognition_service",
                )
                Log.i(
                    "CU41Voice",
                    "native recognition sdk=${Build.VERSION.SDK_INT} " +
                        "visibleServices=${services.size} general=$general " +
                        "onDevice=$onDevice defaultPresent=${!selected.isNullOrBlank()}",
                )
                result.success(
                    mapOf(
                        "sdk" to Build.VERSION.SDK_INT,
                        "visibleServices" to services.size,
                        "generalAvailable" to general,
                        "onDeviceAvailable" to onDevice,
                        "defaultServicePresent" to !selected.isNullOrBlank(),
                    ),
                )
            } catch (error: Exception) {
                Log.e("CU41Voice", "native recognition diagnosis failed", error)
                result.error("recognition_diagnosis_failed", error.javaClass.simpleName, null)
            }
        }
    }
}
