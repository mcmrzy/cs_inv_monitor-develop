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
    label: "flutter analyze",
    value: "0 error / 0 warning",
    description: "修改文件新增代码 0 issue（剩余 info 为历史遗留）",
    tone: "success",
  },
  {
    label: "APK release 构建",
    value: "88.7MB",
    description: "R8 缺 BouncyCastle 类已修复，构建成功",
    tone: "success",
  },
  {
    label: "实时轮询",
    value: "60s → 90s",
    description: "退后台暂停、回前台恢复、页面退出停止",
    tone: "success",
  },
  {
    label: "列表缓存优先",
    value: "4 个 Bloc",
    description: "Dashboard / Alarm / Device / Notification 先出缓存再刷新",
    tone: "success",
  },
  {
    label: "新增磁盘缓存",
    value: "3 类",
    description: "地图瓦片、头像、天气（24h TTL）",
    tone: "success",
  },
];

const timelineEvents: TimelineEvent[] = [
  {
    id: "rt01-03",
    timestamp: "2026-08-03",
    title: "轮询治理三件套",
    description:
      "RealtimeDataService 默认间隔 60s→90s（用户确认）；pauseAll/resumeAll 前后台暂停恢复；电站详情 dispose 停止轮询修复泄漏；实时数据成功落盘、启动恢复缓存",
    state: "completed",
    tone: "success",
  },
  {
    id: "ca01-03",
    timestamp: "2026-08-03",
    title: "列表缓存优先推广",
    description:
      "Dashboard 4 请求并行 + 分节容错；Alarm/Device 断网快速失败不再等 30s 超时；Notification 新增落盘缓存与序列化补字段",
    state: "completed",
    tone: "success",
  },
  {
    id: "rs01-02",
    timestamp: "2026-08-03",
    title: "资源磁盘缓存",
    description:
      "自建 CachedNetworkTileProvider（复用 cached_network_image 缓存，零新增依赖）接入两处地图；头像 NetworkImage → CachedNetworkImageProvider",
    state: "completed",
    tone: "success",
  },
  {
    id: "ft01",
    timestamp: "2026-08-03",
    title: "字体打包（用户取消）",
    description:
      "用户确认差异后决定不打包 Noto Sans SC，保留系统字体方案，3 处改动全部回滚，APK 无 +17MB 增量",
    state: "completed",
    tone: "success",
  },
  {
    id: "vf01",
    timestamp: "2026-08-03",
    title: "验证完成",
    description:
      "flutter analyze 0 error/0 warning；flutter build apk --release 构建成功（修复 jiguang_auth 联通 SDK 缺 BouncyCastle 的既有 R8 问题）",
    state: "completed",
    tone: "success",
  },
];

const changeRows: { module: string; change: string; benefit: string; tone: TagTone }[] = [
  {
    module: "RealtimeDataService",
    change: "默认间隔 90s；pauseAll/resumeAll；实时数据落盘 + 启动恢复",
    benefit: "轮询流量降 33%，前后台零空转，断网/冷启动秒出旧数据",
    tone: "success",
  },
  {
    module: "电站详情页",
    change: "dispose 停止全部订阅轮询；天气结果 24h 缓存（lat/lng 键）",
    benefit: "修复轮询泄漏（页面退出后不再后台请求），天气二次进入零请求",
    tone: "success",
  },
  {
    module: "MainShell",
    change: "WidgetsBindingObserver：paused→pauseAll、resumed→resumeAll",
    benefit: "退后台无轮询流量，回前台立即恢复，通知栏下拉不误触",
    tone: "success",
  },
  {
    module: "DashboardBloc",
    change: "缓存优先 emit；4 统计请求 Future.wait 并行 + 分节容错",
    benefit: "首页秒开（先缓存后刷新），任一接口失败不影响其他",
    tone: "success",
  },
  {
    module: "AlarmBloc / DeviceBloc",
    change: "列表缓存优先（isFromCache）；断网快速失败",
    benefit: "断网打开列表立即显示缓存，不再等待 30s 超时",
    tone: "success",
  },
  {
    module: "NotificationBloc",
    change: "系统通知落盘缓存；toJson/fromJson 补 id/fromBackend",
    benefit: "消息中心离线可读，缓存重建保真",
    tone: "success",
  },
  {
    module: "地图（2 处）",
    change: "CachedNetworkTileProvider 接入两处 TileLayer",
    benefit: "重复浏览瓦片零下载、离线可用（默认 30 天/200MB 自动清理）",
    tone: "success",
  },
  {
    module: "头像（2 处）",
    change: "NetworkImage → CachedNetworkImageProvider",
    benefit: "头像重复查看零下载，与瓦片共用同一缓存体系",
    tone: "success",
  },
  {
    module: "Android 构建",
    change: "app 依赖补 bcprov-jdk15to18:1.68",
    benefit: "修复 jiguang_auth 联通取号 SDK 的 R8 Missing class（release 构建既有问题）",
    tone: "success",
  },
];

const changeColumns: TableColumn<(typeof changeRows)[number]>[] = [
  { key: "module", title: "模块", width: "150px" },
  { key: "change", title: "改动", role: "description" },
  {
    key: "benefit",
    title: "收益",
    role: "label",
    render: (row: (typeof changeRows)[number]) => <Tag tone={row.tone}>{row.benefit}</Tag>,
  },
];

const verifyRows = [
  { item: "flutter analyze", expect: "0 error / 0 warning", result: "通过（150 info 均为 test/ 与历史遗留风格提示）" },
  { item: "flutter build apk --release", expect: "构建成功", result: "通过，app-release.apk 88.7MB" },
  { item: "R8 混淆", expect: "无 Missing class", result: "通过（修复后无缺类）" },
  { item: "flutter test", expect: "单元测试通过", result: "沙箱环境 flutter_tester 无法启动（WebSocket 连接失败），非代码问题，建议本机重跑" },
];

const verifyColumns: TableColumn<(typeof verifyRows)[number]>[] = [
  { key: "item", title: "验证项", width: "220px" },
  { key: "expect", title: "预期", role: "description" },
  { key: "result", title: "实测结果", role: "label" },
];

const evidenceItems: ReferenceItem[] = [
  {
    id: "tile",
    label: "地图瓦片缓存 Provider",
    description: "inv_app/lib/core/widgets/map_tile_provider.dart（新建）",
    kind: "file",
  },
  {
    id: "realtime",
    label: "轮询治理核心",
    description: "inv_app/lib/core/services/realtime_data_service.dart",
    kind: "file",
  },
  {
    id: "lifecycle",
    label: "前后台暂停恢复",
    description: "inv_app/lib/core/router/app_router.dart（MainShell）",
    kind: "file",
  },
  {
    id: "dashboard",
    label: "缓存优先 + 并行",
    description: "inv_app/lib/features/dashboard/presentation/bloc/dashboard_bloc.dart",
    kind: "file",
  },
  {
    id: "gradle",
    label: "R8 修复",
    description: "inv_app/android/app/build.gradle.kts（bcprov 依赖）",
    kind: "file",
  },
  {
    id: "apk",
    label: "构建产物",
    description: "inv_app/build/app/outputs/flutter-apk/app-release.apk（88.7MB）",
    kind: "file",
  },
];

export default function AppOfflineBandwidthOptimizationReport() {
  return (
    <ReportShell width="wide" ariaLabel="App 离线优先与带宽优化完成报告">
      <Stack gap="section">
        <header>
          <Stack gap="component">
            <H1>App 离线优先与带宽优化完成报告</H1>
            <Text tone="secondary">
              执行日期 2026-08-03 · 覆盖 inv_app（Flutter）离线优先改造：轮询治理、缓存优先、资源磁盘缓存 · 计划：
              App离线优先与带宽优化_task-a24
            </Text>
            <MetricsGrid variant="header" columns={5} items={headlineMetrics} />
          </Stack>
        </header>

        <ReportSection title="执行摘要" divided>
          <Stack gap="container">
            <Text>
              围绕「尽量打包进本地、尽量减少开启时间和服务器带宽」的目标完成 10 项改造：轮询间隔 60s→90s 并支持
              前后台暂停/恢复、电站详情退出即停（修复轮询泄漏）、实时数据落盘缓存；Dashboard/Alarm/Device/Notification
              四个列表全部缓存优先（stale-while-revalidate）；地图瓦片与头像接入磁盘缓存（零新增依赖）；天气 24h 缓存。
              字体打包按用户最终决定取消并完全回滚。flutter analyze 0 error/0 warning，release APK 构建成功。
            </Text>
            <Timeline density="compact" events={timelineEvents} />
          </Stack>
        </ReportSection>

        <ReportSection title="关键改动清单" divided>
          <Table columns={changeColumns} rows={changeRows} rowKey="module" density="compact" />
        </ReportSection>

        <ReportSection title="验证证据" divided>
          <Stack gap="container">
            <Callout tone="success" title="构建与静态检查通过">
              flutter analyze：0 error / 0 warning（修改文件新增代码 0 issue，剩余 150 条 info 均为 test/ 与历史遗留
              风格提示）；flutter build apk --release 成功产出 app-release.apk（88.7MB）。
            </Callout>
            <Table columns={verifyColumns} rows={verifyRows} rowKey="item" density="compact" />
          </Stack>
        </ReportSection>

        <ReportSection title="真机验证清单（待执行）" divided>
          <Stack gap="component">
            <Text>以下验证需在真机 + 服务器 access log 环境执行：</Text>
            <Text>1. 冷启动进入首页速度（缓存秒开）；统计页先出缓存再刷新。</Text>
            <Text>2. 断网打开电站详情/统计/告警显示缓存数据；无数据场景提示网络错误。</Text>
            <Text>3. 电站详情退出后服务器 access log 无后续轮询请求。</Text>
            <Text>4. App 退后台 2 分钟无轮询请求、回前台恢复。</Text>
            <Text>5. 地图第二次打开无瓦片网络请求；详情页天气第二次进入无 open-meteo 请求。</Text>
            <Text>6. 头像页重复进入无图片下载请求。</Text>
          </Stack>
        </ReportSection>

        <ReportSection title="风险与说明" divided>
          <Stack gap="container">
            <RiskCallout
              level="low"
              title="沙箱环境限制：flutter_tester 无法启动"
              message="flutter test 在本环境报 WebSocketException（Invalid WebSocket upgrade request），为测试进程连接问题而非断言失败，建议在本机重跑 realtime_data_service_test.dart 等用例。"
            />
            <RiskCallout
              level="low"
              title="额外修复：jiguang_auth 联通 SDK R8 缺类"
              message="release 构建首次暴露 jverification 3.3.1 联通取号 SDK 缺少 BouncyCastle 的既有问题（debug 不跑 R8 未暴露），已在 app/build.gradle.kts 按极光官方要求补 bcprov-jdk15to18:1.68。"
            />
            <Stack gap="component">
              <Text>1. 轮询 90s 对实时告警无影响：告警走 SSE 推送（notification SSE + alarmStream），不依赖轮询。</Text>
              <Text>2. 瓦片/头像缓存复用 cached_network_image 内置 flutter_cache_manager（默认 30 天过期、200MB 上限自动清理）。</Text>
              <Text>3. 生产链路 gzip 已由 api-gateway 中间件覆盖，后端无需改动。</Text>
            </Stack>
          </Stack>
        </ReportSection>

        <ReportSection title="证据文件索引" divided>
          <ReferencePanel items={evidenceItems} columns={2} />
        </ReportSection>
      </Stack>
    </ReportShell>
  );
}
