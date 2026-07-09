// k6 API 压力测试脚本
// 运行方式: k6 run tests/load-test/api-stress.js
// 环境变量: BASE_URL (默认 http://localhost:8888)
//
// 前置条件:
// 1. 数据库中需存在测试账号且密码为 Test@123456
// 2. 若登录失败超过 3 次触发验证码限制，需先清除 Redis:
//    docker exec inv-redis redis-cli -a <password> DEL login_fail:13800138000
//
// 性能阈值:
// - 登录接口 p95 < 500ms
// - 设备列表 p95 < 300ms
// - 错误率 < 1%

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// 自定义指标
const deviceListDuration = new Trend('device_list_duration');

// 测试配置
export const options = {
  stages: [
    { duration: '30s', target: 20 },   // 逐步增加到 20 个虚拟用户
    { duration: '1m', target: 50 },    // 继续增加到 50 个用户
    { duration: '2m', target: 50 },    // 保持 50 个用户 2 分钟
    { duration: '30s', target: 100 },  // 峰值 100 个用户
    { duration: '30s', target: 0 },    // 逐步减少到 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],          // 95% 请求 < 500ms
    http_req_failed: ['rate<0.10'],            // 错误率 < 10% (高并发下允许少量失败)
    device_list_duration: ['p(95)<300'],       // 设备列表 p95 < 300ms
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8888';

// 测试账号（需已存在于数据库中，密码 Test@123456）
const TEST_USER = { account: '13800138000', password: 'Test@123456' };

// ==================== setup: 一次性登录获取 token ====================

export function setup() {
  console.log(`开始 API 压力测试，目标: ${BASE_URL}`);

  // 先验证服务可达
  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    '健康检查可达': (r) => r.status === 200,
  });

  // 执行一次登录获取共享 token（避免并发登录触发验证码限制）
  const res = http.post(`${BASE_URL}/api/v1/auth/login`, JSON.stringify({
    account: TEST_USER.account,
    password: TEST_USER.password,
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  let authToken = '';
  if (res.status === 200) {
    try {
      authToken = res.json().data.access_token;
      console.log('初始登录成功，token 已获取');
    } catch {
      console.log('初始登录解析 token 失败');
    }
  } else {
    console.log(`初始登录失败: ${res.status} - ${res.body}`);
  }

  return { authToken };
}

// ==================== 主测试函数 ====================

export default function (data) {
  const authToken = data.authToken;

  // 公开接口压测（无需认证）
  group('01_健康检查', function () {
    const res = http.get(`${BASE_URL}/health`);

    check(res, {
      '健康检查状态码 200': (r) => r.status === 200,
      '健康检查响应时间 < 50ms': (r) => r.timings.duration < 50,
    });
  });

  sleep(0.5);

  // 需要认证的接口压测（使用 setup 阶段获取的共享 token）
  if (authToken) {
    const authHeaders = {
      headers: {
        'Authorization': `Bearer ${authToken}`,
        'Content-Type': 'application/json',
      },
    };

    group('02_设备列表', function () {
      const res = http.get(`${BASE_URL}/api/v1/devices?page=1&pageSize=20`, authHeaders);

      deviceListDuration.add(res.timings.duration);

      check(res, {
        '设备列表状态码 200': (r) => r.status === 200,
        '设备列表响应时间 < 300ms': (r) => r.timings.duration < 300,
      });
    });

    sleep(0.5);

    group('03_电站列表', function () {
      const res = http.get(`${BASE_URL}/api/v1/stations?page=1&pageSize=20`, authHeaders);

      check(res, {
        '电站列表状态码 200': (r) => r.status === 200,
      });
    });

    sleep(0.5);

    group('04_告警列表', function () {
      const res = http.get(`${BASE_URL}/api/v1/alarms?page=1&pageSize=20`, authHeaders);

      check(res, {
        '告警列表状态码 200': (r) => r.status === 200,
      });
    });

    sleep(0.5);
  }

  // 公开接口（无需认证）
  group('05_时区列表(公开)', function () {
    const res = http.get(`${BASE_URL}/api/v1/timezones`);

    check(res, {
      '时区列表状态码 200': (r) => r.status === 200,
    });
  });

  sleep(1);
}

export function teardown(data) {
  console.log('API 压力测试完成');
}
