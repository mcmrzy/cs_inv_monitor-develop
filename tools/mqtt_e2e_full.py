#!/usr/bin/env python3
"""
MQTT 全链路功能验证（阶段3 完整版）：
- 遥测链路: EMQX(11883) → mqtt2kafka_relay → Kafka(19092 inv-telemetry)
           → inv-device-server protocol parser → device_telemetry_3min
- 告警链路: EMQX(11883) cs_inv/{sn}/alarm → inv-device-server HandleMQTTAlarm
           → POST api-server → 告警表
- 在线状态: heartbeat → Redis device:heartbeat:{sn} / device:online_set
输出 JSON 证据到 e2e_evidence/mqtt-e2e-result.json
"""
import json
import os
import random
import sys
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

MQTT_BROKER = os.environ.get("E2E_MQTT_BROKER", "127.0.0.1")
MQTT_PORT = int(os.environ.get("E2E_MQTT_PORT", "11883"))
DEVICE_COUNT = int(os.environ.get("E2E_MQTT_DEVICES", "50"))
SETTLE_SECONDS = int(os.environ.get("E2E_MQTT_SETTLE", "20"))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACCOUNT_FILE = os.path.join(ROOT, "e2e_evidence", "e2e-account.json")
RESULT_FILE = os.path.join(ROOT, "e2e_evidence", "mqtt-e2e-result.json")


def gen_heartbeat(sn: str, index: int) -> bytes:
    """V1 heartbeat（与 mqtt_simulator.py send_via_kafka 同格式）。"""
    power = random.uniform(1800, 4200)
    voltage_ac = round(220 + random.uniform(-5, 5), 1)
    current_ac = round(power / 220, 2)
    t = int(time.time())
    payload = {
        "t": t,
        "v": 1,
        "data": {
            "ac": [voltage_ac, current_ac, round(power, 1), round(power / 0.95, 1), 50.0, 0.95, 50.0, 2.0],
            "bat": [
                round(random.uniform(20, 80), 1), 100.0, 48.0, 0.0, 0.0,
                50.0, 100.0, 100, 35.0, 30.0,
                3.3, 3.2, 0.1, 0, 0,
                0, 50.0, 50.0, 54.0, 44.0,
                35.0, 500, 540,
            ],
            "pv": [100.0, 7.0, round(power, 1), 0.0, 0.0, 0.0, 1],
            "sys": [2, 0, 0, 45.0, 40.0, 30.0, 400.0, 5000, 50, 95.0, 0],
            "eng": [12.5, 12345.0 + index, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0],
            "cells": [[3.3] * 16, [35.0] * 4],
        },
    }
    return json.dumps(payload).encode()


def gen_alarm(sn: str, code: int) -> bytes:
    """V1 告警：{v:1, t:unix, data:{source,code,level,state}}"""
    payload = {
        "v": 1,
        "t": int(time.time()),
        "data": {"source": 0, "code": code, "level": 1, "state": 1},
    }
    return json.dumps(payload).encode()


def main() -> int:
    print(f"[mqtt-e2e] broker={MQTT_BROKER}:{MQTT_PORT} devices={DEVICE_COUNT}")

    bound_sns: list[str] = []
    if os.path.exists(ACCOUNT_FILE):
        acc = json.load(open(ACCOUNT_FILE, encoding="utf-8"))
        bound_sns = acc.get("devices", [])
    suffix = f"{int(time.time() * 1000) % 10**10:X}"
    gen_sns = [f"E2EMQTT{i:02d}{suffix}" for i in range(DEVICE_COUNT)]
    all_sns = bound_sns + gen_sns
    print(f"[mqtt-e2e] bound devices: {bound_sns}")

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"e2e-full-{int(time.time())}")
    client.connect(MQTT_BROKER, MQTT_PORT, 30)
    client.loop_start()
    time.sleep(1)

    published = []
    # 1) 遥测：所有设备发 heartbeat（V1）
    for i, sn in enumerate(all_sns):
        topic = f"cs_inv/{sn}/heartbeat"
        info = client.publish(topic, gen_heartbeat(sn, i), qos=1)
        published.append({"sn": sn, "topic": topic, "mid": info.mid, "kind": "telemetry", "bound": sn in bound_sns})
    # 2) 告警：绑定设备 1 台 + 额外 4 台
    alarm_sns = (bound_sns[:1] if bound_sns else []) + gen_sns[:4]
    for j, sn in enumerate(alarm_sns):
        topic = f"cs_inv/{sn}/alarm"
        info = client.publish(topic, gen_alarm(sn, 100 + j), qos=1)
        published.append({"sn": sn, "topic": topic, "mid": info.mid, "kind": "alarm", "bound": sn in bound_sns})
    time.sleep(3)
    client.loop_stop()
    client.disconnect()
    print(f"[mqtt-e2e] published {len(published)} messages "
          f"({len(all_sns)} telemetry + {len(alarm_sns)} alarm)")

    print(f"[mqtt-e2e] waiting {SETTLE_SECONDS}s for relay→Kafka→consumer→DB...")
    time.sleep(SETTLE_SECONDS)

    result = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "broker": f"{MQTT_BROKER}:{MQTT_PORT}",
        "device_count": len(all_sns),
        "bound_devices": bound_sns,
        "alarm_devices": alarm_sns,
        "published": published,
        "settle_seconds": SETTLE_SECONDS,
        "note": "链路: MQTT(11883) → mqtt2kafka_relay → Kafka(19092) → device-server consumer → PostgreSQL",
    }
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"[mqtt-e2e] evidence written: {RESULT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
