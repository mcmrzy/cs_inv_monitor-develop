#!/usr/bin/env python3
"""
MQTT → Kafka 转发器（测试用，模拟 mqtt-kafka-bridge 的 webhook 行为）。

订阅测试 EMQX(127.0.0.1:11883) 的 cs_inv/# 主题，按 mqtt-kafka-bridge 的
RawMessage 格式转发到测试 Kafka(127.0.0.1:19092)：
  - alarm / data/alarm → inv-alerts
  - 其他 → inv-telemetry

用法: python tools/mqtt2kafka_relay.py [--broker 127.0.0.1:11883] [--kafka 127.0.0.1:19092]
"""

import argparse
import json
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt
from kafka import KafkaProducer

STATS = {"relayed": 0, "errors": 0}


def extract_msg_type(topic: str) -> str:
    parts = topic.split("/")
    if len(parts) >= 3:
        return "/".join(parts[2:])
    return "unknown"


def on_connect(client, userdata, flags, reason_code, properties=None):
    """断线重连后必须重新订阅，否则收不到任何消息。"""
    client.subscribe("cs_inv/#", qos=1)
    print(f"[relay] (re)connected rc={reason_code}, re-subscribed cs_inv/#")


def on_disconnect(client, userdata, flags, reason_code, properties=None):
    print(f"[relay] disconnected rc={reason_code}, waiting reconnect...")


def on_message(client, userdata, msg):
    topic = msg.topic
    sn = topic.split("/")[1] if len(topic.split("/")) >= 2 else ""
    msg_type = extract_msg_type(topic)
    if not sn or msg_type == "unknown":
        STATS["errors"] += 1
        return
    try:
        payload_obj = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        payload_obj = msg.payload.decode("utf-8", errors="replace")

    raw = {
        "sn": sn,
        "client_id": "e2e-relay",
        "msg_type": msg_type,
        "mqtt_topic": topic,
        "qos": msg.qos,
        "payload": payload_obj,
        "received_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    kafka_topic = "inv-alerts" if msg_type in ("alarm", "data/alarm") else "inv-telemetry"
    producer = userdata["producer"]
    try:
        # 异步发送：同步 future.get 会在高流量下阻塞 MQTT 回调，
        # 导致 EMQX 缓冲区拥塞（conn_congestion）与消息丢失。
        producer.send(
            kafka_topic,
            key=sn.encode(),
            value=json.dumps(raw, ensure_ascii=False).encode("utf-8"),
        )
        STATS["relayed"] += 1
    except Exception as e:  # noqa: BLE001
        STATS["errors"] += 1
        print(f"[relay] error {topic}: {e}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--broker", default="127.0.0.1:11883", help="MQTT broker host:port")
    parser.add_argument("--kafka", default="127.0.0.1:19092", help="Kafka bootstrap host:port")
    args = parser.parse_args()

    broker_host, broker_port = args.broker.rsplit(":", 1)
    producer = KafkaProducer(
        bootstrap_servers=args.kafka,
        acks=1,
        retries=3,
        linger_ms=20,
        batch_size=32768,
    )
    client = mqtt.Client(
        mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"e2e-mqtt2kafka-relay-{int(time.time() * 1000)}",
        clean_session=True,
    )
    client.user_data_set({"producer": producer})
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    client.connect(broker_host, int(broker_port), 30)
    client.loop_start()
    print(f"[relay] connecting to {args.broker}, forwarding to Kafka {args.kafka}")
    try:
        while True:
            time.sleep(30)
            producer.flush(timeout=30)
            print(f"[relay] stats: relayed={STATS['relayed']} errors={STATS['errors']}")
    except KeyboardInterrupt:
        pass
    finally:
        client.loop_stop()
        client.disconnect()
        producer.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
