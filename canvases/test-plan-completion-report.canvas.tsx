import {
  Callout,
  Grid,
  H1,
  MetricsGrid,
  ReferencePanel,
  ReportSection,
  ReportShell,
  RiskCallout,
  Stack,
  Table,
  Tag,
  Text,
  Timeline,
  canvasImage,
} from "qoder/canvas";
import type {
  MetricItem,
  ReferenceItem,
  TableColumn,
  TagTone,
  TimelineEvent,
} from "qoder/canvas";

const headlineMetrics: MetricItem[] = [
  {
    label: "集成测试",
    value: "ok 52.454s",
    description: "第 9 轮全绿，15 迁移基线",
    tone: "success",
  },
  {
    label: "Playwright E2E",
    value: "11 / 11",
    description: "28.3s，13 张截图证据",
    tone: "success",
  },
  {
    label: "前端 vitest",
    value: "232 用例",
    description: "26 文件，tsc 0 错误",
    tone: "success",
  },
  {
    label: "Flutter 测试",
    value: "271 通过",
    description: "~4 跳过，analyze 通过",
    tone: "success",
  },
  {
    label: "k6 压测 p95",
    value: "11.5ms",
    description: "2002 req / 0 错误",
    tone: "success",
  },
];

const stageRows = [
  { stage: "阶段 0", scope: "隔离测试环境准备", result: "7 容器健康、网关 18888/Redis 16379/EMQX 11883 就绪、压测账号注册" },
  { stage: "阶段 1", scope: "单元测试（4 Go 模块 race+coverage+vet / 契约 / 前端 / Flutter）", result: "全绿；jwt 75.2%、sn 87.6%、routes 95.8% 等覆盖率达标" },
  { stage: "阶段 2", scope: "集成测试（认证/设备/组织/认领/MQTT 全链路/迁移基线）", result: "ok 52.454s 全绿（期间修复 4 类测试问题）" },
  { stage: "阶段 3", scope: "Playwright E2E + MQTT 业务链路验证", result: "11/11 通过；52 台设备遥测→在线+落库+告警 5 条" },
  { stage: "阶段 4", scope: "压力测试（benchmark/k6/mqtt-load/5000 台模拟）", result: "k6 p95 11.5ms、5000/5000 落库 0 错误、资源占用极低；压测数据已清理" },
  { stage: "阶段 5", scope: "安全测试（套件/govulncheck/npm audit/敏感信息/RBAC）", result: "套件全绿；grpc 与 path-to-regexp 漏洞已修复；RBAC 403/401/200 实测通过" },
];

const stageColumns: TableColumn<(typeof stageRows)[number]>[] = [
  { key: "stage", title: "阶段", width: "72px" },
  { key: "scope", title: "范围", role: "description" },
  { key: "result", title: "结果", role: "label" },
];

const defectRows: { level: string; desc: string; status: string; tone: TagTone }[] = [
  { level: "P0", desc: "repositories.go 引用已删列（role/parent_id）导致集成测试编译失败", status: "已修复", tone: "success" },
  { level: "P0", desc: "admin_handler.go SystemMonitor 接口与前端联动断裂", status: "已修复", tone: "success" },
  { level: "P1", desc: "api-server 组级限流 10/20 req 击穿正常流量（k6 p95 175ms）", status: "已修复", tone: "success" },
  { level: "P1", desc: "mqtt2kafka_relay 同步发送阻塞导致消息丢失（1830/5000）", status: "已修复", tone: "success" },
  { level: "P1", desc: "Kafka 消息 0 落库（advertised listener 不可达 + offset 失效，测试环境配置问题）", status: "已解决", tone: "success" },
  { level: "P2", desc: "集成测试 4 项（invitation role_id / 手机号唯一 / 064 契约 role_code / cross_tenant 解析）", status: "已修复", tone: "success" },
  { level: "P2", desc: "react-router 2 个 moderate 漏洞（v6 无修复版，SPA 场景不可利用）", status: "记录，建议升级 v7", tone: "warning" },
  { level: "P2", desc: "本地 Go 工具链 1.26.4（标准库 2 漏洞，容器 1.26.5 已覆盖）", status: "记录，建议升级", tone: "warning" },
  { level: "P2", desc: "前端 build chunk >500kB 警告", status: "记录，建议按需拆包", tone: "warning" },
];

const defectColumns: TableColumn<(typeof defectRows)[number]>[] = [
  { key: "level", title: "级别", width: "64px" },
  { key: "desc", title: "缺陷描述", role: "description" },
  {
    key: "status",
    title: "状态",
    width: "200px",
    render: (row: (typeof defectRows)[number]) => (
      <Tag tone={row.tone}>{row.status}</Tag>
    ),
  },
];

const vulnRows: { id: string; target: string; sev: string; status: string; tone: TagTone }[] = [
  { id: "GO-2026-6061", target: "grpc v1.81.1（xDS RBAC/HTTP2）", sev: "漏洞", status: "已修复：升级 v1.82.1，重扫消失", tone: "success" },
  { id: "GO-2026-5856", target: "crypto/tls ECH 隐私泄露（标准库 1.26.4）", sev: "漏洞", status: "容器 golang:1.26.5 覆盖；本地工具链需升级", tone: "warning" },
  { id: "GO-2026-4970", target: "os 符号链接 root escape（标准库 1.26.4）", sev: "漏洞", status: "同上，容器已覆盖", tone: "warning" },
  { id: "path-to-regexp", target: "ReDoS ×2（经 pro-layout，8.0.0-8.3.0）", sev: "high", status: "已修复：overrides 强制 8.4.2，回归全绿", tone: "success" },
  { id: "react-router", target: "open redirect / deserializeErrors（≤7.17.0）", sev: "moderate ×2", status: "v6 无修复版；SPA 实际不可利用，建议升级 v7", tone: "warning" },
];

const vulnColumns: TableColumn<(typeof vulnRows)[number]>[] = [
  { key: "id", title: "漏洞", width: "140px" },
  { key: "target", title: "影响对象", role: "description" },
  { key: "sev", title: "严重级", width: "96px" },
  {
    key: "status",
    title: "状态",
    render: (row: (typeof vulnRows)[number]) => (
      <Tag tone={row.tone}>{row.status}</Tag>
    ),
  },
];

const rbacRows = [
  { scene: "普通用户 load2026 → /api/v1/admin/users", expect: "403 权限不足", result: "通过" },
  { scene: "无 token → /api/v1/admin/users", expect: "401 未认证", result: "通过" },
  { scene: "普通用户 → /api/v1/auth/profile、/api/v1/devices", expect: "200 正常", result: "通过" },
];

const rbacColumns: TableColumn<(typeof rbacRows)[number]>[] = [
  { key: "scene", title: "场景", role: "description" },
  { key: "expect", title: "预期", width: "200px" },
  { key: "result", title: "实测", width: "100px" },
];

const timelineEvents: TimelineEvent[] = [
  {
    id: "phase0-3",
    timestamp: "2026-08-02",
    title: "阶段 0-3 完成",
    description: "隔离环境就绪；4 模块单测/契约/前端/Flutter 全绿；集成测试第 9 轮 ok 52.454s；Playwright E2E 11/11",
    state: "completed",
    tone: "success",
  },
  {
    id: "phase4",
    timestamp: "2026-08-03",
    title: "阶段 4 压力测试完成",
    description: "修复 P1 限流击穿后 k6 p95 11.5ms；mqtt-load 200 客户端 0 错误；5000 台模拟双模式全落库；压测数据清理归零",
    state: "completed",
    tone: "success",
  },
  {
    id: "phase5",
    timestamp: "2026-08-03",
    title: "阶段 5 安全测试完成",
    description: "安全套件全绿；grpc 升级 v1.82.1、path-to-regexp overrides 8.4.2 修复高危漏洞；敏感信息扫描与 RBAC 越权验证通过",
    state: "completed",
    tone: "success",
  },
  {
    id: "phase6",
    timestamp: "2026-08-03",
    title: "阶段 6 汇总报告",
    description: "test-report-full.md 生成（10 节，含缺陷清单 9 项与风险建议）；证据文件归档 e2e_evidence/",
    state: "completed",
    tone: "success",
  },
];

const evidenceItems: ReferenceItem[] = [
  { id: "integration", label: "集成测试结果", description: "integration-test-9-final.txt（ok 52.454s）", kind: "file" },
  { id: "e2e", label: "Playwright E2E 结果", description: "playwright-results.json / e2e-final.txt + 13 张截图", kind: "file" },
  { id: "k6", label: "k6 压测摘要", description: "k6-api-lite-rerun-summary.json（p95 11.5ms）/ k6-api-100vu-after-fix.json", kind: "file" },
  { id: "flutter", label: "Flutter 结果", description: "flutter-final.txt（+271 ~4）/ flutter-analyze.txt", kind: "file" },
  { id: "mqtt", label: "MQTT 链路验证", description: "mqtt-e2e-result.json / mqtt-e2e-db-check.json / docker-stats-samples.txt", kind: "file" },
  { id: "report", label: "全量测试报告", description: "test-report-full.md（项目根目录，10 节）", kind: "doc" },
];

const screenshots = [
  { src: canvasImage("../e2e_evidence/e2e-login-success.png"), alt: "E2E 登录成功", caption: "登录成功（account + 密码）" },
  { src: canvasImage("../e2e_evidence/e2e-page-dashboard.png"), alt: "E2E 仪表盘", caption: "仪表盘数据卡片渲染" },
  { src: canvasImage("../e2e_evidence/e2e-page-devices.png"), alt: "E2E 设备列表", caption: "设备列表 → 详情导航" },
  { src: canvasImage("../e2e_evidence/e2e-page-alerts.png"), alt: "E2E 告警中心", caption: "告警列表加载与筛选" },
  { src: canvasImage("../e2e_evidence/e2e-lang-zh.png"), alt: "E2E 中文界面", caption: "语言切换（中文）" },
  { src: canvasImage("../e2e_evidence/e2e-lang-en.png"), alt: "E2E 英文界面", caption: "语言切换（英文）" },
];

export default function TestPlanCompletionReport() {
  return (
    <ReportShell width="wide" ariaLabel="cs_inv_monitor 全方面测试完成报告">
      <Stack gap="section">
        <header>
          <Stack gap="component">
            <H1>cs_inv_monitor 全方面测试完成报告</H1>
            <Text tone="secondary">
              执行日期 2026-08-02 ~ 2026-08-03 · 隔离测试环境 docker-compose.test.yml（不触碰本地开发与生产数据）
            </Text>
            <MetricsGrid variant="header" columns={5} items={headlineMetrics} />
          </Stack>
        </header>

        <ReportSection title="执行摘要" divided>
          <Stack gap="container">
            <Text>
              6 阶段全部执行完毕：环境准备 → 单元测试 → 集成测试 → 前端 E2E 与业务链路 → 完整压力测试 → 安全测试。
              累计发现并修复 8 类缺陷（含 2 个 P0、1 个 P1 限流击穿、1 个 P1 消息丢失），
              剩余 3 项 P2 低风险记录项与 1 项外部工作流风险已纳入建议。
            </Text>
            <Timeline density="compact" events={timelineEvents} />
          </Stack>
        </ReportSection>

        <ReportSection title="阶段结果总览" divided>
          <Table columns={stageColumns} rows={stageRows} rowKey="stage" density="compact" />
        </ReportSection>

        <ReportSection title="缺陷修复清单" divided>
          <Table columns={defectColumns} rows={defectRows} rowKey="desc" density="compact" />
        </ReportSection>

        <ReportSection title="安全测试结论" divided>
          <Stack gap="container">
            <Callout tone="success" title="安全套件全绿（ok 0.375s）">
              CORS 白名单、暴力破解防护、SQL 注入 9 类 payload、XSS/路径遍历、JWT 弱密钥/篡改/None 算法攻击拒绝——全套通过。
              敏感信息扫描确认仓库无私钥/硬编码凭据，生产配置使用环境变量占位符。
            </Callout>
            <Table columns={vulnColumns} rows={vulnRows} rowKey="id" density="compact" />
            <Table columns={rbacColumns} rows={rbacRows} rowKey="scene" density="compact" />
          </Stack>
        </ReportSection>

        <ReportSection title="E2E 证据截图（Playwright，11/11）" divided>
          <Grid columns={2} gap="container">
            {screenshots.map((s) => (
              <Stack key={s.alt} gap="micro" align="start">
                <img
                  src={s.src}
                  alt={s.alt}
                  style={{
                    width: "100%",
                    borderRadius: 8,
                    border: "1px solid var(--canvas-stroke-tertiary, rgba(128,128,128,0.25))",
                  }}
                />
                <Text size="small" tone="secondary">
                  {s.caption}
                </Text>
              </Stack>
            ))}
          </Grid>
        </ReportSection>

        <ReportSection title="风险与后续建议" divided>
          <Stack gap="container">
            <RiskCallout
              level="medium"
              title="外部工作流风险：权限体系迁移中间态"
              message="报告生成时工作区存在「成员身份=组织类型模型」迁移的 92 个未提交文件，business-api 处于编译中间态（model.User 移除 Role 等）。该迁移不属于本测试计划，建议迁移完成后重跑阶段 1/2 回归。"
            />
            <Stack gap="component">
              <Text>1. 本地 Go 工具链升级至 1.26.5（容器 golang:1.26.5-alpine 已覆盖标准库漏洞）。</Text>
              <Text>2. react-router 升级 v7 前评估 SPA 路由 API 兼容性（v6 无安全修复版）。</Text>
              <Text>3. 前端构建产物按路由进一步拆分（vendor-antd 大块）。</Text>
            </Stack>
          </Stack>
        </ReportSection>

        <ReportSection title="证据文件索引（e2e_evidence/）" divided>
          <ReferencePanel items={evidenceItems} columns={2} />
        </ReportSection>
      </Stack>
    </ReportShell>
  );
}
