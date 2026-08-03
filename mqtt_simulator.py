#!/usr/bin/env python3
"""
MQTT设备模拟脚本
模拟10000台设备发送遥测数据到EMQX broker
支持两种模式：
1. MQTT模式：通过EMQX webhook转发到Kafka
2. API模式：直接通过API Server发送数据
"""

import paho.mqtt.client as mqtt
import json
import time
import random
import os
import sys
from datetime import datetime, timezone
import ssl
import requests
from kafka import KafkaProducer

# MQTT配置（默认指向隔离测试环境 EMQX，可用环境变量覆盖）
MQTT_BROKER = os.environ.get("SIM_MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.environ.get("SIM_MQTT_PORT", "11883"))
MQTT_USERNAME = os.environ.get("SIM_MQTT_USER", "")
MQTT_PASSWORD = os.environ.get("SIM_MQTT_PASS", "")
MQTT_TLS_INSECURE = True
MQTT_TLS = os.environ.get("SIM_MQTT_TLS", "0") == "1"

# API配置（直接通过API Server发送数据）
API_SERVER = "http://localhost:8081"
INTERNAL_KEY = "local-dev-internal-key-1234567890"

# Kafka配置（可用环境变量覆盖，默认指向隔离测试环境）
KAFKA_BROKER = os.environ.get("SIM_KAFKA_BROKER", "127.0.0.1:19092")
KAFKA_TOPIC = os.environ.get("SIM_KAFKA_TOPIC", "inv-telemetry")

# 运行模式：mqtt、api 或 kafka
RUN_MODE = os.environ.get("SIM_RUN_MODE", "mqtt")

# 设备数量
DEVICE_COUNT = int(os.environ.get("SIM_DEVICE_COUNT", "5000"))
BATCH_SIZE = 100  # 每批发送设备数
BATCH_DELAY = 0.5  # 批次间延迟秒

# 统计
success_count = 0
fail_count = 0
total_count = 0

def on_connect(client, userdata, flags, rc, properties=None):
    global connected
    if rc == 0:
        print(f"Connected to MQTT Broker: {MQTT_BROKER}:{MQTT_PORT}")
        connected = True
    else:
        print(f"Connection failed with code: {rc}")
        connected = False

def on_publish(client, userdata, mid, reason_code=None, properties=None):
    global success_count
    success_count += 1

def on_disconnect(client, userdata, disconnect_flags=None, reason_code=None, properties=None):
    if reason_code and reason_code != 0:
        print(f"Unexpected disconnection. RC: {reason_code}")

def generate_telemetry_data(device_sn, device_index):
    """生成设备遥测数据"""
    # 基础值 + 随机波动
    base_voltage_pv = 100 + random.uniform(-10, 30)
    base_current_pv = 7 + random.uniform(-2, 3)
    base_power = base_voltage_pv * base_current_pv
    
    return {
        "sn": device_sn,
        "topic": f"cs_inv/{device_sn}/telemetry",
        "data": {
            "voltage_pv1": round(base_voltage_pv, 1),
            "current_pv1": round(base_current_pv, 2),
            "power_pv1": round(base_power, 1),
            "voltage_ac": round(220 + random.uniform(-5, 5), 1),
            "current_ac": round(base_power / 220, 2),
            "power_ac": round(base_power * 0.95, 1),
            "frequency_ac": round(50 + random.uniform(-0.1, 0.1), 2),
            "temperature": round(45 + random.uniform(-5, 15), 1),
            "status": 1,
            "work_state": 2,
            "fault_code": 0,
            "battery_soc": round(random.uniform(20, 80), 1),
            "battery_voltage": round(48 + random.uniform(-2, 2), 1),
            "runtime_hours": random.randint(100, 10000)
        },
        "daily_pv": round(random.uniform(5, 20), 2),
        "total_pv": round(random.uniform(100, 5000), 2),
        "timestamp": int(time.time())
    }

def send_via_api(device_sn, data):
    """通过API Server直接发送数据"""
    url = f"{API_SERVER}/api/v1/internal/device-data-batch"
    headers = {
        "Content-Type": "application/json",
        "X-Internal-Key": INTERNAL_KEY
    }
    payload = [{
        "sn": device_sn,
        "topic": "data/status",
        "data": data["data"],
        "timestamp": data["timestamp"]
    }]
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
        return response.status_code == 200
    except Exception as e:
        print(f"API error for {device_sn}: {e}")
        return False

def send_via_kafka(device_sn, data):
    """通过Kafka直接发送消息，模拟device-server的消费流程"""
    global kafka_producer
    
    # 构建V1 heartbeat格式的消息
    # ac: [voltage, current, active_power, apparent_power, frequency, power_factor, load_percent, voltage_thd]
    # bat: [soc, soh, voltage, current, power, capacity_remain, capacity_total, cycle_count, temp_max, temp_min, 
    #       cell_voltage_max, cell_voltage_min, cell_voltage_diff, state, protect_status, fault_code,
    #       max_charge_current, max_discharge_current, charge_voltage_ref, discharge_cutoff_voltage, temperature,
    #       charge_request_current_x10, charge_request_voltage_x10]
    # pv: [pv1_voltage, pv1_current, pv1_power, pv2_voltage, pv2_current, pv2_power, mppt_state]
    # sys: [work_state, fault_code, alarm_code, inverter_temperature, mos_temperature, ambient_temperature,
    #       dc_bus_voltage, runtime_hours, fan_speed_percent, efficiency, system_mode]
    # eng: [daily_pv, total_pv, daily_charge, total_charge, daily_discharge, total_discharge, daily_load, total_load,
    #       total_charge_capacity, total_discharge_capacity, total_charge_time, total_discharge_time]
    # cells: [[cell_voltages...], [cell_temperatures...]]
    
    voltage_ac = data["data"]["voltage_ac"]
    current_ac = data["data"]["current_ac"]
    power_ac = data["data"]["power_ac"]
    apparent_power = power_ac / 0.95
    
    # ac: 8 elements
    ac = [voltage_ac, current_ac, power_ac, apparent_power, 50.0, 0.95, 50.0, 2.0]
    
    # bat: 23 elements (with defaults for missing fields)
    bat = [
        data["data"]["battery_soc"],  # soc
        100.0,  # soh
        data["data"]["battery_voltage"],  # voltage
        0.0,  # current
        0.0,  # power
        50.0,  # capacity_remain
        100.0,  # capacity_total
        100,  # cycle_count
        35.0,  # temp_max
        30.0,  # temp_min
        3.3,  # cell_voltage_max
        3.2,  # cell_voltage_min
        0.1,  # cell_voltage_diff
        0,  # state
        0,  # protect_status
        data["data"]["fault_code"],  # fault_code
        50.0,  # max_charge_current
        50.0,  # max_discharge_current
        54.0,  # charge_voltage_ref
        44.0,  # discharge_cutoff_voltage
        35.0,  # temperature
        500,  # charge_request_current_x10
        540,  # charge_request_voltage_x10
    ]
    
    # pv: 7 elements
    pv1_power = data["data"]["power_pv1"]
    pv = [data["data"]["voltage_pv1"], data["data"]["current_pv1"], pv1_power, 0.0, 0.0, 0.0, 1]
    
    # sys: 11 elements
    sys = [
        data["data"]["work_state"],  # work_state
        data["data"]["fault_code"],  # fault_code
        0,  # alarm_code
        data["data"]["temperature"],  # inverter_temperature
        40.0,  # mos_temperature
        30.0,  # ambient_temperature
        400.0,  # dc_bus_voltage
        data["data"]["runtime_hours"],  # runtime_hours
        50,  # fan_speed_percent
        95.0,  # efficiency
        0,  # system_mode
    ]
    
    # eng: 12 elements
    eng = [
        data["daily_pv"],  # daily_pv
        data["total_pv"],  # total_pv
        0.0,  # daily_charge
        0.0,  # total_charge
        0.0,  # daily_discharge
        0.0,  # total_discharge
        0.0,  # daily_load
        0.0,  # total_load
        0.0,  # total_charge_capacity
        0.0,  # total_discharge_capacity
        0,  # total_charge_time
        0,  # total_discharge_time
    ]
    
    # cells: 2 arrays [voltages[16], temperatures[4]]
    cell_voltages = [3.3] * 16
    cell_temperatures = [35.0] * 4
    cells = [cell_voltages, cell_temperatures]
    
    heartbeat_payload = {
        "t": int(time.time()),
        "v": 1,
        "data": {
            "ac": ac,
            "bat": bat,
            "pv": pv,
            "sys": sys,
            "eng": eng,
            "cells": cells
        }
    }
    
    kafka_msg = {
        "sn": device_sn,
        "client_id": f"simulator-{device_sn}",
        "msg_type": "heartbeat",
        "mqtt_topic": f"cs_inv/{device_sn}/heartbeat",
        "qos": 0,
        "payload": heartbeat_payload,
        "received_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    
    try:
        kafka_producer.send(KAFKA_TOPIC, key=device_sn.encode(), value=json.dumps(kafka_msg).encode())
        return True
    except Exception as e:
        print(f"Kafka error for {device_sn}: {e}")
        return False

def main():
    global success_count, fail_count, total_count, kafka_producer
    
    print(f"Starting Device Simulator")
    print(f"Mode: {RUN_MODE}")
    if RUN_MODE == "mqtt":
        print(f"Broker: {MQTT_BROKER}:{MQTT_PORT}")
    elif RUN_MODE == "api":
        print(f"API Server: {API_SERVER}")
    else:
        print(f"Kafka Broker: {KAFKA_BROKER}")
    print(f"Devices: {DEVICE_COUNT}")
    print(f"Batch Size: {BATCH_SIZE}")
    print("-" * 50)
    
    # 初始化Kafka Producer
    if RUN_MODE == "kafka":
        try:
            kafka_producer = KafkaProducer(
                bootstrap_servers=KAFKA_BROKER,
                value_serializer=lambda v: v,
                key_serializer=lambda k: k,
                acks=1,
                retries=3
            )
            print(f"Connected to Kafka: {KAFKA_BROKER}")
        except Exception as e:
            print(f"Kafka connection error: {e}")
            return
    
    # 记录开始时间
    start_time = time.time()
    
    if RUN_MODE == "mqtt":
        # MQTT模式
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="device-simulator-001")
        if MQTT_USERNAME:
            client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
        
        # TLS配置（仅生产 broker 启用）
        if MQTT_TLS:
            client.tls_set(cert_reqs=ssl.CERT_NONE)
            client.tls_insecure_set(MQTT_TLS_INSECURE)
        
        # 设置回调
        client.on_connect = on_connect
        client.on_publish = on_publish
        client.on_disconnect = on_disconnect
        
        # 连接
        print(f"Connecting to broker...")
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, 60)
            client.loop_start()
        except Exception as e:
            print(f"Connection error: {e}")
            return
        
        # 等待连接
        time.sleep(2)
        
        # 发送数据
        print(f"Sending telemetry data via MQTT...")
        
        for batch_start in range(0, DEVICE_COUNT, BATCH_SIZE):
            batch_end = min(batch_start + BATCH_SIZE, DEVICE_COUNT)
            batch_size = batch_end - batch_start
            
            for i in range(batch_start, batch_end):
                device_sn = f"MASS-TEST-{i + 1}"
                topic = f"cs_inv/{device_sn}/telemetry"
                data = generate_telemetry_data(device_sn, i)
                
                try:
                    result = client.publish(topic, json.dumps(data), qos=0)
                    if result.rc != mqtt.MQTT_ERR_SUCCESS:
                        fail_count += 1
                    total_count += 1
                except Exception as e:
                    fail_count += 1
                    print(f"Error publishing {device_sn}: {e}")
            
            # 显示进度
            progress = (batch_end / DEVICE_COUNT) * 100
            elapsed = time.time() - start_time
            rate = batch_end / elapsed if elapsed > 0 else 0
            print(f"  Progress: {batch_end}/{DEVICE_COUNT} ({progress:.1f}%) - Rate: {rate:.1f} msg/s")
            
            # 批次延迟
            if batch_end < DEVICE_COUNT:
                time.sleep(BATCH_DELAY)
        
        # 等待消息发送完成
        time.sleep(2)
        
        # 断开连接
        client.loop_stop()
        client.disconnect()
    elif RUN_MODE == "api":
        # API模式
        print(f"Sending telemetry data via API...")
        
        for batch_start in range(0, DEVICE_COUNT, BATCH_SIZE):
            batch_end = min(batch_start + BATCH_SIZE, DEVICE_COUNT)
            batch_size = batch_end - batch_start
            
            for i in range(batch_start, batch_end):
                device_sn = f"MASS-TEST-{i + 1}"
                data = generate_telemetry_data(device_sn, i)
                
                if send_via_api(device_sn, data):
                    success_count += 1
                else:
                    fail_count += 1
                total_count += 1
            
            # 显示进度
            progress = (batch_end / DEVICE_COUNT) * 100
            elapsed = time.time() - start_time
            rate = batch_end / elapsed if elapsed > 0 else 0
            print(f"  Progress: {batch_end}/{DEVICE_COUNT} ({progress:.1f}%) - Rate: {rate:.1f} msg/s")
            
            # 批次延迟
            if batch_end < DEVICE_COUNT:
                time.sleep(BATCH_DELAY)
    else:
        # Kafka模式
        print(f"Sending telemetry data via Kafka...")
        
        for batch_start in range(0, DEVICE_COUNT, BATCH_SIZE):
            batch_end = min(batch_start + BATCH_SIZE, DEVICE_COUNT)
            batch_size = batch_end - batch_start
            
            for i in range(batch_start, batch_end):
                device_sn = f"MASS-TEST-{i + 1}"
                data = generate_telemetry_data(device_sn, i)
                
                if send_via_kafka(device_sn, data):
                    success_count += 1
                else:
                    fail_count += 1
                total_count += 1
            
            # 显示进度
            progress = (batch_end / DEVICE_COUNT) * 100
            elapsed = time.time() - start_time
            rate = batch_end / elapsed if elapsed > 0 else 0
            print(f"  Progress: {batch_end}/{DEVICE_COUNT} ({progress:.1f}%) - Rate: {rate:.1f} msg/s")
            
            # 批次延迟
            if batch_end < DEVICE_COUNT:
                time.sleep(BATCH_DELAY)
        
        # 冲刷并关闭Kafka Producer（异步 send 后必须 flush 等待全部发送完成）
        if kafka_producer:
            try:
                kafka_producer.flush(timeout=120)
            except Exception as e:
                print(f"Kafka flush error: {e}")
            kafka_producer.close()
    
    # 计算统计
    total_time = time.time() - start_time
    
    print("\n" + "=" * 50)
    print(f"Test Results")
    print("=" * 50)
    print(f"Success: {success_count}")
    print(f"Fail: {fail_count}")
    print(f"Total Time: {total_time:.2f} seconds")
    print(f"Throughput: {success_count / total_time:.2f} msg/s")
    print(f"Total Messages: {total_count}")

if __name__ == "__main__":
    main()
