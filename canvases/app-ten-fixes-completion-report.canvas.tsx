import {
  Callout,
  Divider,
  Grid,
  H1,
  H2,
  Stack,
  Stat,
  Table,
  Tag,
  Text,
  Timeline,
} from 'qoder/canvas';

export default function AppTenFixesCompletionReport() {
  return (
    <Stack gap={20}>
      <H1>App 十项体验修复 — 完成报告</H1>
      <Text tone="secondary">
        依据 Spec《App十项体验修复》全部 10 项需求 + 最终验证，逐项实现并通过
        flutter analyze / flutter test / Go build·vet·test 验证。
      </Text>

      <Grid columns={4} gap={16}>
        <Stat value="10/10" label="Spec 需求完成" tone="success" />
        <Stat value="382" label="Flutter 测试全部通过" tone="success" />
        <Stat value="0" label="analyze error/warning" tone="success" />
        <Stat value="4" label="Go 模块构建通过" tone="success" />
      </Grid>

      <Divider />

      <H2>成果摘要（逐项）</H2>
      <Table
        headers={['#', '需求', '实现结果']}
        rows={[
          ['1', '补光灯改暗光检测', '不再开机即亮：连续 5 秒扫不到码自动亮灯，识别到二维码自动熄灭；文案改「暗光补光」'],
          ['2', '首启引导向导化', '重写为三屏 PageView 向导（创建电站→添加设备→配网），进度条 + 编号子步骤 + 「去完成」直达，完成自动进入下一步'],
          ['3', '帮助中心 FAQ 变少', '后端默认 FAQ 由 3 条恢复为 10 条且空数组兜底；App fallback 内置 10 条，后端失败/空配置均完整展示'],
          ['4', '工单页三项', '提交按钮改渐变胶囊；Tab 状态驱动 + 请求序号守卫修复筛选；按 Tab 缓存，切换不重建、刷新保留旧列表'],
          ['5', 'OTA 中心横幅', '本地离网模式入口横幅已移除（/local-mode 路由保留）'],
          ['6', '本地升级双 Tab', '固定「BLE 升级 / AP 升级」双 Tab，扫描式列表只显示扫到的设备（去前缀显示 SN），并修复路由未解析 channel 参数的问题'],
          ['7', '固件库打开失败', '根因为 build 阶段 setState；改为首帧回调处理缓存态 + 错误态重试面板'],
          ['8', '升级历史全设备统一', '后端新增 GET /api/v1/ota/history（DataPermission 数据域，含 source/upgrade_package_id）；App 移除选设备层，列表显示 SN'],
          ['9', '离网直连设置', '移除本地模式开关；SN 去前缀直显；新增「已绑定」徽标（keyStore 判定）；文案去除「支持 CS 协议」并说明未绑定不自动连接'],
          ['10', '编辑设备小字', '改为「修改设备别名与备注」，编辑页与长按入口共用一处修复'],
        ]}
      />

      <H2>关键步骤</H2>
      <Timeline
        events={[
          {
            title: '定位根因',
            description:
              '并行检索 10 个问题涉及的页面/服务/后端接口：固件库 setState-during-build、FAQ 默认值缺失、Tab 乱序覆盖、型号白名单过滤 BLE 等',
            tone: 'info',
          },
          {
            title: '并行实施',
            description:
              '5 个子代理并行处理互不冲突的任务（FAQ/工单页/升级历史/本地升级/离网设置），l10n 文案由主代理统一收口避免冲突',
            tone: 'info',
          },
          {
            title: '主代理收尾',
            description:
              '暗光检测、向导页重写、OTA 横幅移除、固件库修复、编辑设备文案、全部 l10n 中英文落库',
            tone: 'info',
          },
          {
            title: '最终验证',
            description:
              'flutter analyze（0 error/0 warning）、flutter test（382 通过）、go build（4 模块）、go vet、go test 全部包通过',
            tone: 'success',
          },
        ]}
      />

      <H2>改动文件（主要）</H2>
      <Table
        headers={['模块', '文件', '改动']}
        rows={[
          ['Flutter', 'features/device/.../add_device_page.dart', '暗光检测补光逻辑与文案'],
          ['Flutter', 'features/onboarding/.../setup_guide_page.dart', '重写为三屏向导'],
          ['Flutter', 'features/support/.../work_orders_page.dart', '按钮美化 + Tab 筛选 + 缓存不重建'],
          ['Flutter', 'features/ota/.../local_upgrade_page.dart', '双 Tab 扫描式重写'],
          ['Flutter', 'features/ota/.../firmware_library_page.dart', 'build 期 setState 崩溃修复'],
          ['Flutter', 'features/ota/.../upgrade_history_page.dart / ota_tab_page.dart', '统一历史 / 去横幅'],
          ['Flutter', 'features/profile/.../offline_mode_settings_page.dart', '去开关 + 已绑定徽标 + SN 显示'],
          ['Flutter', 'core/router/app_router.dart、l10n/app_zh.dart、l10n/app_en.dart', 'channel 参数解析、双语新增/修订约 30 条'],
          ['Go', 'business-api/internal/handler/config_handler.go', '默认 FAQ 10 条 + 空数组兜底'],
          ['Go', 'business-api/internal/{repository,service,handler}/ota_*.go、cmd/main.go', '新增 GET /ota/history 全链路'],
          ['Flutter', 'core/services/help_center_config_service.dart', '内置 10 条 FAQ 兜底'],
        ]}
      />

      <H2>验证证据</H2>
      <Table
        headers={['验证项', '命令', '结果']}
        rows={[
          ['Flutter 静态分析', 'flutter analyze', '0 error / 0 warning（289 条均为既有 info 级提示）'],
          ['Flutter 测试', 'flutter test', '382 项全部通过（含工单页 widget 测试）'],
          ['Go 构建', 'go build ./...（business-api / api-gateway / device-communication / mqtt-kafka-bridge）', '4 个模块全部通过'],
          ['Go 静态检查', 'go vet ./...（business-api）', '通过'],
          ['Go 测试', 'go test ./...（business-api）', '17 个包全部 ok'],
          ['完成审计', '逐项 grep / 读文件核对 Spec 10 项', '全部在位（含负向项：横幅与本地模式开关已删除）'],
        ]}
      />

      <Callout tone="success" title="最终结论">
        Spec 全部 10 项需求已实现并验证；安全疑问（BLE 自动连接仅限已绑定设备、绑定需设备端校验铭牌
        PIN）已在功能与文案中体现。可提交打包测试。
      </Callout>

      <Stack gap={4}>
        <Text tone="secondary" size="small">
          遗留提示（非本轮范围）：BleCommunicationService 的 OTA UUID 为占位符（待固件团队确认），可能影响
          BLE 升级通道可用性；Android WiFi 扫描存在系统限流（4 次/2 分钟）。
        </Text>
        <Tag tone="neutral">cs_inv_monitor · inv_app · business-api</Tag>
      </Stack>
    </Stack>
  );
}
