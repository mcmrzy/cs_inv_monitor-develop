import {
  Callout,
  H1,
  MetricsGrid,
  ReferencePanel,
  ReportSection,
  ReportShell,
  Stack,
  Table,
  Tag,
  Text,
  Timeline,
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
    label: "根因",
    value: "防抖计数放大",
    description: "外部探活调用参与离线确认计数，启动瞬间 3 次误报打满阈值",
    tone: "warning",
  },
  {
    label: "修复文件",
    value: "2 个",
    description: "network_status_service.dart + offline_banner.dart",
    tone: "success",
  },
  {
    label: "flutter analyze",
    value: "0 error / 0 warning",
    description: "全项目通过，公共 API 零破坏",
    tone: "success",
  },
  {
    label: "误判窗口",
    value: "4 秒 → 0",
    description: "正常网络下不再误判离线，真断网仍 4 秒内正确确认",
    tone: "success",
  },
];

const timelineEvents: TimelineEvent[] = [
  {
    id: "root-cause",
    timestamp: "2026-08-03",
    title: "根因定位",
    description:
      "首页 OfflineBanner 读全局离线快照；NetworkStatusService 防抖设计中 checkConnectivity() 每次外部调用都累计 _offlineStreak，冷启动初始化+登录跳转探活+定时重试 3 次 none 误报即误判离线",
    state: "completed",
    tone: "warning",
  },
  {
    id: "fix-core",
    timestamp: "2026-08-03",
    title: "核心修复（network_status_service.dart）",
    description:
      "外部 checkConnectivity() 不再参与离线确认计数（仅乐观返回+安排重试）；确认仅由系统事件与定时重试驱动；判离线后持续重试，网络恢复自动回在线",
    state: "completed",
    tone: "success",
  },
  {
    id: "fix-banner",
    timestamp: "2026-08-03",
    title: "顺带修复（offline_banner.dart）",
    description:
      "OfflineBanner / OfflineIndicator 补 dispose 取消 statusStream 订阅，修复监听泄漏",
    state: "completed",
    tone: "success",
  },
  {
    id: "verify",
    timestamp: "2026-08-03",
    title: "验证完成",
    description:
      "flutter analyze 全项目 0 error/0 warning；无 _handleResult 残留引用；公共 API 兼容；四场景逻辑推演通过（正常登录/真断网/断网恢复/并发探活）",
    state: "completed",
    tone: "success",
  },
];

const fixRows: { item: string; before: string; after: string; tone: TagTone }[] = [
  {
    item: "离线确认计数",
    before: "任何调用方 checkConnectivity() 返回 none 都累计 _offlineStreak（并发放大）",
    after: "仅系统状态事件与定时重试累计；外部探活只乐观返回并安排延迟重试",
    tone: "success",
  },
  {
    item: "离线恢复",
    before: "判离线后不再安排重试，恢复依赖系统事件（可能长期卡离线）",
    after: "判离线后持续每 2s 重试，网络恢复自动广播在线",
    tone: "success",
  },
  {
    item: "监听泄漏",
    before: "OfflineBanner/OfflineIndicator dispose 未取消 statusStream 订阅",
    after: "dispose 取消订阅",
    tone: "success",
  },
];

const fixColumns: TableColumn<(typeof fixRows)[number]>[] = [
  { key: "item", title: "项目", width: "120px" },
  { key: "before", title: "修复前", role: "description" },
  {
    key: "after",
    title: "修复后",
    role: "label",
    render: (row: (typeof fixRows)[number]) => <Tag tone={row.tone}>{row.after}</Tag>,
  },
];

const scenarioRows = [
  { scenario: "正常冷启动 + 快速登录", result: "streak 最多 1~2，达不到阈值 3 → 红条不闪现", pass: "通过（推演）" },
  { scenario: "真实断网", result: "系统事件/重试 3 次确认（约 4 秒）→ 红条正确显示", pass: "通过（推演）" },
  { scenario: "断网恢复", result: "持续重试撞到 wifi → 自动回在线 → 红条消失", pass: "通过（推演）" },
  { scenario: "多 Bloc 并发探活", result: "checkConnectivity 不累计计数，互不干扰", pass: "通过（推演）" },
];

const scenarioColumns: TableColumn<(typeof scenarioRows)[number]>[] = [
  { key: "scenario", title: "场景", role: "description" },
  { key: "result", title: "行为", role: "label" },
  { key: "pass", title: "验证", width: "100px" },
];

const evidenceItems: ReferenceItem[] = [
  {
    id: "service",
    label: "核心修复",
    description: "inv_app/lib/core/services/network_status_service.dart",
    kind: "file",
  },
  {
    id: "banner",
    label: "监听泄漏修复",
    description: "inv_app/lib/core/widgets/offline_banner.dart",
    kind: "file",
  },
  {
    id: "callsite",
    label: "调用方（零改动兼容）",
    description: "station_bloc / dashboard_bloc / alarm_bloc / main.dart / service_locator.dart",
    kind: "file",
  },
];

export default function OfflineBannerFlashFixReport() {
  return (
    <ReportShell width="wide" ariaLabel="登录后断网提示闪现修复报告">
      <Stack gap="section">
        <header>
          <Stack gap="component">
            <H1>登录后"断网提示"闪现 1 秒 — 根因与修复报告</H1>
            <Text tone="secondary">
              执行日期 2026-08-03 · 问题：每次登录进入首页，顶部红色"无网络连接"横幅闪现约 1 秒后消失
            </Text>
            <MetricsGrid variant="header" columns={4} items={headlineMetrics} />
          </Stack>
        </header>

        <ReportSection title="根因分析" divided>
          <Stack gap="container">
            <Callout tone="warning" title="防抖计数被外部调用放大">
              NetworkStatusService 的"连续确认"设计缺陷：每次外部调用 checkConnectivity() 返回 none 都累计
              _offlineStreak。冷启动瞬间 Android 网络栈未就绪，初始化检查（t=0）→ 定时重试（t≈2s）→ 登录跳转后
              StationBloc 探活（t≈3s）恰好 3 次误报 none，阈值打满 → 误判离线 → 首页 OfflineBanner 读快照显示红条 →
              网络栈就绪后恢复在线 → 闪现约 1 秒。
            </Callout>
            <Timeline density="compact" events={timelineEvents} />
          </Stack>
        </ReportSection>

        <ReportSection title="修复内容" divided>
          <Table columns={fixColumns} rows={fixRows} rowKey="item" density="compact" />
        </ReportSection>

        <ReportSection title="行为推演" divided>
          <Table columns={scenarioColumns} rows={scenarioRows} rowKey="scenario" density="compact" />
        </ReportSection>

        <ReportSection title="验证与后续" divided>
          <Stack gap="container">
            <Callout tone="success" title="静态验证通过">
              flutter analyze 全项目 0 error / 0 warning（150 条 info 均为改动前历史遗留）；无 _handleResult 残留引用；
              公共 API（checkConnectivity/initialize/statusStream/isOffline）签名不变，所有调用方零改动兼容。
            </Callout>
            <Text tone="secondary">
              沙箱环境 flutter_tester 无法启动（WebSocket 连接失败，环境限制），单元测试需在本机重跑；
              真机复验：连续登录 2~3 次红条不再闪现；开飞行模式 4 秒后红条正常显示，关飞行模式自动消失。
            </Text>
          </Stack>
        </ReportSection>

        <ReportSection title="证据文件索引" divided>
          <ReferencePanel items={evidenceItems} columns={3} />
        </ReportSection>
      </Stack>
    </ReportShell>
  );
}
