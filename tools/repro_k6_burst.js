// 精确复现 k6 lite 的请求模式：20 VU × 每 3s 周期 5 组请求（组间 0.5s）
// 打印每个非 200 响应的状态码 + body 片段，统计分布
const BASE = 'http://127.0.0.1:18888';
const ACCOUNT = '17018742674';
const PASSWORD = 'E2e@2026Pass';

async function login() {
  const res = await fetch(`${BASE}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account: ACCOUNT, password: PASSWORD }),
  });
  const j = await res.json();
  return j.data?.access_token || '';
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const token = await login();
  console.log('token:', token ? 'OK' : 'FAIL');
  const authHeaders = { Authorization: `Bearer ${token}` };

  const stats = {}; // status -> {count, sample}
  const VUS = 20;
  const CYCLES = 6; // 6 × 3s = 18s

  const paths = [
    { name: 'health', url: `${BASE}/health`, headers: {} },
    { name: 'devices', url: `${BASE}/api/v1/devices?page=1&pageSize=20`, headers: authHeaders },
    { name: 'stations', url: `${BASE}/api/v1/stations?page=1&pageSize=20`, headers: authHeaders },
    { name: 'alarms', url: `${BASE}/api/v1/alarms?page=1&pageSize=20`, headers: authHeaders },
    { name: 'timezones', url: `${BASE}/api/v1/timezones`, headers: {} },
  ];

  for (let cycle = 0; cycle < CYCLES; cycle++) {
    for (let g = 0; g < paths.length; g++) {
      const group = paths[g];
      // 20 VU 同时发出同组请求
      const results = await Promise.all(
        Array.from({ length: VUS }, () =>
          fetch(group.url, { headers: group.headers }).then(async (r) => {
            const body = await r.text();
            return { status: r.status, body };
          })
        )
      );
      const byStatus = {};
      for (const r of results) {
        byStatus[r.status] = (byStatus[r.status] || 0) + 1;
        if (!stats[r.status]) stats[r.status] = { count: 0, sample: '' };
        stats[r.status].count++;
        if (!stats[r.status].sample && r.status !== 200) {
          stats[r.status].sample = `${group.name} | ${r.body.slice(0, 160)}`;
        }
      }
      console.log(
        `cycle=${cycle + 1} group=${group.name.padEnd(10)} ` +
          Object.entries(byStatus).map(([s, c]) => `${s}:${c}`).join(' ')
      );
      await sleep(500);
    }
  }

  console.log('\n===== 汇总 =====');
  for (const [status, v] of Object.entries(stats)) {
    console.log(`HTTP ${status}: ${v.count} 次${v.sample ? `  样例: ${v.sample}` : ''}`);
  }
}

main().catch((e) => {
  console.error('FATAL:', e.message);
  process.exit(1);
});
