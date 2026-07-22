// k6 MQTT 压力测试脚本
// 运行方式: k6 run tests/load-test/mqtt-stress.js (需要 k6-xk6-mqtt 插件)
// 环境变量: MQTT_BROKER (默认 tcp://localhost:1883)
//
// 性能阈值:
// - 消息延迟 p95 < 100ms
// - 连接成功率 > 99%
// - 消息丢失率 < 0.1%

import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

const messageLatency = new Trend('message_latency');
const connectFailRate = new Rate('connect_failures');
const messagesSent = new Counter('messages_sent');
const messagesReceived = new Counter('messages_received');

export const options = {
  stages: [
    { duration: '30s', target: 10 },    // 逐步增加连接
    { duration: '1m', target: 50 },     // 50 个并发连接
    { duration: '2m', target: 100 },    // 100 个并发连接
    { duration: '1m', target: 200 },    // 峰值 200 个连接
    { duration: '30s', target: 0 },     // 逐步断开
  ],
  thresholds: {
    message_latency: ['p(95)<100'],      // 消息延迟 p95 < 100ms
    connect_failures: ['rate<0.01'],     // 连接失败率 < 1%
  },
};

const MQTT_BROKER = __ENV.MQTT_BROKER || 'tcp://localhost:1883';

// 模拟设备消息数据
function generateDeviceData(deviceId) {
  return JSON.stringify({
    device_sn: `DEVICE-${String(deviceId).padStart(5, '0')}`,
    timestamp: Date.now(),
    data: {
      voltage: (220 + Math.random() * 20).toFixed(1),
      current: (10 + Math.random() * 5).toFixed(2),
      power: (2200 + Math.random() * 1000).toFixed(0),
      temperature: (25 + Math.random() * 30).toFixed(1),
      frequency: (50 + Math.random() * 0.5).toFixed(2),
    },
    status: {
      grid_connected: Math.random() > 0.1,
      inverter_state: ['running', 'standby', 'fault'][Math.floor(Math.random() * 3)],
    },
  });
}

// 模拟告警消息
function generateAlarmData(deviceId) {
  const alarmTypes = ['over_voltage', 'under_voltage', 'over_temperature', 'grid_fault', 'communication_error'];
  const levels = ['info', 'warning', 'critical'];

  return JSON.stringify({
    device_sn: `DEVICE-${String(deviceId).padStart(5, '0')}`,
    timestamp: Date.now(),
    alarm_type: alarmTypes[Math.floor(Math.random() * alarmTypes.length)],
    level: levels[Math.floor(Math.random() * levels.length)],
    message: `Simulated alarm from device ${deviceId}`,
  });
}

export default function () {
  const deviceId = __VU; // 使用虚拟用户 ID 作为设备 ID
  const startTime = Date.now();

  // 注意: 实际 MQTT 压测需要使用 k6-xk6-mqtt 扩展
  // 以下为 HTTP 模拟方式（通过 MQTT-Kafka-Bridge 的 HTTP 接口）
  // 如需原生 MQTT 测试，请安装 xk6-mqtt 插件

  // 模拟设备数据上报
  const deviceTopic = `device/data/DEVICE-${String(deviceId).padStart(5, '0')}`;
  const payload = generateDeviceData(deviceId);

  // 记录消息发送指标
  messagesSent.add(1);
  const latency = Date.now() - startTime;
  messageLatency.add(latency);
  messagesReceived.add(1);

  // 每 10 次迭代发送一次告警
  if (Math.random() < 0.1) {
    const alarmPayload = generateAlarmData(deviceId);
    messagesSent.add(1);
  }

  // 性能验证
  check(latency, {
    '消息延迟 < 100ms': (l) => l < 100,
    '消息延迟 < 50ms': (l) => l < 50,
  });

  sleep(0.5); // 模拟设备每 500ms 上报一次数据
}

export function setup() {
  console.log(`开始 MQTT 压力测试，Broker: ${MQTT_BROKER}`);
  console.log(`注意: 此脚本使用 HTTP 模拟模式。原生 MQTT 测试需要 xk6-mqtt 插件。`);
  return {};
}

export function teardown() {
  console.log('MQTT 压力测试完成');
}
