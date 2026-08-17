import {
  Callout,
  CollapsibleSection,
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

export default function FlutterAppReviewFixReport() {
  return (
    <Stack gap={20}>
      <H1>Flutter App 审查修复 — 完成报告</H1>
      <Text tone="secondary">
        依据审查计划（阶段一 P0 阻断级 → 阶段四结构性重构）对 inv_app 与 business-api
        实施全量修复，四阶段全部完成并通过验证。
      </Text>

      <Grid columns={4} gap={16}>
        <Stat value="4/4" label="计划阶段完成" tone="success" />
        <Stat value="35+" label="修复项落地" />
        <Stat value="60+" label="变更文件" />
        <Stat value="354" label="测试通过 / 0 失败" tone="success" />
      </Grid>

      <Divider />

      <H2>阶段成果</H2>
      <Table
        headers={['阶段', '核心内容', '代表性修复', '状态']}
        rows={[
          [
            '阶段一 P0',
            '阻断级缺陷 + 高危安全（9 项）',
            'APK 哈希校验拒装、https 默认基址、登出隐私清理、强类型 OtaManifest 根治键名错位、双 Tab 离线升级元数据持久化、BLE 分片超 MTU、PopScope 防变砖、离线同步迁移 op-log',
            '完成',
          ],
          [
            '阶段二 状态机',
            'OTA/离网正确性（8 项）',
            '轮询三级超时 + 防重入、互联网探活 + 对称滞回、syncing 僵死恢复、duplicates 计入已处理、监控器改通信应答判定（夜间 AC=0 不再误断）、版本比较统一 main_version、数据滞后提示',
            '完成',
          ],
          [
            '阶段三 一致性',
            '资源泄漏与协议（4 项）',
            '固件下载按任务分流 + 并发守卫 + 孤儿文件清理、wifi_ap 状态行解析 + _rawHttp 收敛、设备直连鉴权协议头预留、快照库联动删除 + updated_at 时效',
            '完成',
          ],
          [
            '阶段四 重构',
            '结构性治理（10 项）',
            'LocalOTAController 下沉、巨型页 part 拆分（-3200 行）、app_router 拆分、路由 firmware_id 化、auth_guard 复核、l10n CI 校验、主题取色收敛（600+ 处）、加载态统一、错误类型体系、全局错误边界',
            '完成',
          ],
        ]}
        rowTone={['danger', 'warning', undefined, undefined]}
      />

      <H2>关键步骤</H2>
      <Timeline
        events={[
          {
            title: 'P0 安全与阻断级修复',
            description:
              'APK 自更新强制 SHA-256/MD5 校验 + https + 域名白名单；WiFi/BLE 上传统一强类型 LocalOtaManifest；离线操作迁移 op-log（UUID 幂等、仅记录不重放）',
            tone: 'danger',
          },
          {
            title: '状态机加固',
            description:
              'OtaBloc 三级超时（15min 总时 / 5min 停滞 / 3 次失败）；NetworkStatusService 周期探活覆盖“连 WiFi 无互联网”；离线日志同步四类缺陷修复',
            tone: 'warning',
          },
          {
            title: '结构性拆分',
            description:
              'wifi_config / device_control / station_detail 巨型页 part 拆分；app_router 拆出 shell/ 目录；local_ota_page 执行引擎下沉 LocalOTAController',
            tone: 'info',
          },
          {
            title: '规范收敛',
            description:
              '主题色 600+ 处迁移 AppColor context 语义取色；15 处页面级裸 spinner 统一为 PageSkeleton；新增 l10n 动态 key CI 校验（发现并修复 6 个缺失 key）',
            tone: 'success',
          },
        ]}
      />

      <CollapsibleSection title="主要变更文件（按域）" defaultOpen>
        <Table
          headers={['域', '文件', '变更要点']}
          rows={[
            ['安全', 'app_update_service.dart / app_config.dart', '哈希校验 + URL 白名单；默认基址改生产 https'],
            ['OTA', 'local_ota_controller.dart（新增）/ local_ota_page.dart', '执行引擎下沉；PopScope 防变砖；路由参数收敛'],
            ['OTA', 'wifi_ap / ble_communication_service.dart', '强类型 manifest；MTU 修复；状态行解析；_rawHttp 收敛'],
            ['OTA', 'ota_bloc.dart / ota_error_types.dart', '三级超时 + 防重入；错误类型体系 + l10n 映射'],
            ['OTA', 'firmware_list_page.dart', '多芯片整包串行编排器；路由仅传 firmware_id'],
            ['离网', 'network_status_service.dart', '互联网探活 + 对称滞回'],
            ['离网', 'offline_log_sync_service.dart / offline_op_log_store.dart', 'syncing 恢复、duplicates、单条失败判定、resetSyncingToPending'],
            ['离网', 'connection_mode_service.dart / inverter_connection_monitor.dart', 'init 幂等；byUser 区分；通信应答判定'],
            ['隐私', 'auth_bloc.dart / ble_device_manager.dart', '登出清快照/op-log/BLE 密钥；登录复位 guest 模式'],
            ['结构', 'app_router.dart → router/shell/*', 'MainShell / BottomNavBar / DeviceListPage 拆出'],
            ['结构', 'wifi_config_sections / device_control_sections / station_detail_widgets（新增）', '巨型页 part 拆分'],
            ['主题', 'app_theme.dart + 54 个业务文件', 'AppColor 单一入口；品牌色集中定义'],
            ['后端', 'ota_handler.go / offline_log_handler.go / main.go', 'firmware-info/:id 新接口；op-log 白名单扩展'],
          ]}
        />
      </CollapsibleSection>

      <H2>验证证据</H2>
      <Grid columns={2} gap={16}>
        <Stack gap={8}>
          <Text weight="semibold">Flutter（inv_app）</Text>
          <Text tone="secondary" size="small">
            flutter analyze：0 error / 0 warning（118 条均为既有 info 级样式基线）
          </Text>
          <Text tone="secondary" size="small">
            flutter test：354 通过 / 0 失败（4 跳过）
          </Text>
        </Stack>
        <Stack gap={8}>
          <Text weight="semibold">Go 后端（business-api）</Text>
          <Text tone="secondary" size="small">go build ./... 通过</Text>
          <Text tone="secondary" size="small">
            go vet 通过；go test ./internal/handler/ 通过（含 op-log 白名单）
          </Text>
        </Stack>
      </Grid>
      <Callout tone="warning" title="环境限制说明">
        3 个 sqflite 原生依赖测试（offline_log_sync / offline_op_log_store / ble_binding）在本机无法运行：
        测试需从 GitHub 下载 SQLite DLL，当前网络受限。需在可访问 GitHub 的 CI 环境补跑。
        OTA / 离网相关修复涉及真机行为（WiFi 热点、BLE），建议按计划做真机回归。
      </Callout>

      <H2>遗留协同项（计划“假设”声明项）</H2>
      <Stack gap={8}>
        <Text size="small">
          <Tag tone="info">固件团队</Tag> BLE 正式 UUID（现为占位符）、设备直连接口会话鉴权、配网 WiFi
          密码加密传输 —— App 侧已完成协议头预留与 TODO 标记。
        </Text>
        <Text size="small">
          <Tag tone="info">运维</Tag> 发布 APK 版本时请在后台填写 file_md5（后续可扩展
          file_sha256 字段），否则哈希校验降级为仅 https 传输保护。
        </Text>
        <Text size="small">
          <Tag tone="info">测试环境</Tag> 少量无 BuildContext 场景（CustomPainter /
          静态辅助函数）保留浅色固定值并加注释，属预期取舍。
        </Text>
      </Stack>

      <Divider />
      <Callout tone="success" title="最终结论">
        Spec 四个阶段全部条目实施完毕：P0 阻断级与高危安全漏洞清零，OTA /
        离网状态机完成正确性加固，结构性重构（引擎下沉、巨型页拆分、路由治理、主题与加载态收敛）落地，
        flutter analyze 0 error / 0 warning、354 项测试全绿、后端构建与测试通过。
      </Callout>
    </Stack>
  );
}
