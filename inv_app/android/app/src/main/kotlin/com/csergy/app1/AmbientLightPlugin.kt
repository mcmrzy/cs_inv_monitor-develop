package com.csergy.app1

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * 自研环境光传感器通道：实时推送环境光照度（lux）。
 *
 * 供扫码页「暗光补光」使用：亮度低于阈值才点亮补光灯。
 * 无环境光传感器的机型在 onListen 时推送一次 null，
 * Dart 侧据此回退「持续扫不到码」启发式判据。
 */
class AmbientLightPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private lateinit var channel: EventChannel
    private var sensorManager: SensorManager? = null
    private var listener: SensorEventListener? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = EventChannel(binding.binaryMessenger, "csergy/ambient_light")
        channel.setStreamHandler(this)
        sensorManager = binding.applicationContext
            .getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setStreamHandler(null)
        listener?.let { sensorManager?.unregisterListener(it) }
        listener = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
        if (sensor == null) {
            // 无传感器：通知 Dart 侧回退启发式策略
            events?.success(null)
            return
        }
        val sink = events ?: return
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                sink.success(event.values[0].toDouble())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager?.registerListener(
            listener,
            sensor,
            SensorManager.SENSOR_DELAY_NORMAL,
        )
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { sensorManager?.unregisterListener(it) }
        listener = null
    }
}
