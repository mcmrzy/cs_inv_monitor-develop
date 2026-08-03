// k6 API 性能基线测试（低并发，避免触发网关限流）
// 运行方式: k6 run tests/load-test/api-stress-lite.js
// 环境变量: BASE_URL、TEST_ACCOUNT、TEST_PASSWORD
// 与 api-stress.js 对比：固定 20 VU × 60s，验证无限流干扰下的性能基线
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import exec from 'k6/execution';
import { Trend } from 'k6/metrics';

const deviceListDuration = new Trend('device_list_duration');

export const options = {
  scenarios: {
    baseline: {
      executor: 'constant-vus',
      vus: 20,
      duration: '60s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
    device_list_duration: ['p(95)<300'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8888';
const TEST_USER = { account: __ENV.TEST_ACCOUNT || '', password: __ENV.TEST_PASSWORD || '' };

export function setup() {
  console.log(`开始 API 性能基线测试，目标: ${BASE_URL}`);

  if (!TEST_USER.account || !TEST_USER.password) {
    exec.test.abort('TEST_ACCOUNT and TEST_PASSWORD are required');
  }

  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    '健康检查可达': (r) => r.status === 200,
  });

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
    console.log(`初始登录失败: HTTP ${res.status}`);
  }

  return { authToken };
}

export default function (data) {
  const authToken = data.authToken;

  group('01_健康检查', function () {
    const res = http.get(`${BASE_URL}/health`);
    check(res, {
      '健康检查状态码 200': (r) => r.status === 200,
    });
  });

  sleep(0.5);

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

  group('05_时区列表(公开)', function () {
    const res = http.get(`${BASE_URL}/api/v1/timezones`);
    check(res, {
      '时区列表状态码 200': (r) => r.status === 200,
    });
  });

  sleep(1);
}

export function teardown(data) {
  console.log('API 性能基线测试完成');
}
