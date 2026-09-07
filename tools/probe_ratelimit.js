// 测定网关全局限流器实际生效的 rate/burst（用无路由限流的 /api/v1/timezones 纯净测试）
const BASE = 'http://127.0.0.1:18888';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function burstRequests(n) {
  // 快速连续（无间隔）发 n 个请求，统计 200 数量 → 桶容量
  let ok = 0;
  for (let i = 0; i < n; i++) {
    const res = await fetch(`${BASE}/api/v1/timezones`);
    if (res.status === 200) ok++;
  }
  return ok;
}

async function rateRequests(n, intervalMs) {
  // 固定间隔持续发送，统计通过率 → 实际 rate
  let ok = 0, fail = 0;
  const t0 = Date.now();
  for (let i = 0; i < n; i++) {
    const res = await fetch(`${BASE}/api/v1/timezones`);
    if (res.status === 200) ok++; else fail++;
    await sleep(intervalMs);
  }
  const dur = (Date.now() - t0) / 1000;
  return { ok, fail, dur, rate: (ok / dur).toFixed(1) };
}

async function main() {
  console.log('== 实验1: 桶容量测定（连续无间隔 250 个）==');
  await sleep(15000); // 等桶满
  const burst = await burstRequests(250);
  console.log(`连续 250 个: 200=${burst} 429=${250 - burst}  → burst 容量 ≈ ${burst}`);

  console.log('\n== 实验2: 20/s 持续 20s ==');
  await sleep(15000);
  let r = await rateRequests(400, 50);
  console.log(`20/s×20s: 200=${r.ok} 429=${r.fail} 实际通过率=${r.rate}/s`);

  console.log('\n== 实验3: 50/s 持续 10s ==');
  await sleep(15000);
  r = await rateRequests(500, 20);
  console.log(`50/s×10s: 200=${r.ok} 429=${r.fail} 实际通过率=${r.rate}/s`);

  console.log('\n== 实验4: 100/s 持续 10s ==');
  await sleep(15000);
  r = await rateRequests(1000, 10);
  console.log(`100/s×10s: 200=${r.ok} 429=${r.fail} 实际通过率=${r.rate}/s`);
}

main().catch((e) => { console.error('FATAL:', e.message); process.exit(1); });
