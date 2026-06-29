# 设备型号模块化方案

## 目标

不同型号设备自动显示不同参数、支持不同控制命令、使用不同解析规则——全部通过后台管理页面配置，无需改代码。

## 现状分析

### 已有的基础设施（不需要重做）
- `device_models` / `device_model_field` / `device_model_protocol` 三张表 ✅
- Admin 网页的型号管理 CRUD + DynamicFieldRenderer 等动态组件 ✅
- Device server 的 MetadataRepository + ProtocolAdapter + FieldMapping ✅
- Model field 的 `is_control` 字段用于命令校验 ✅

### 需要改造的硬编码部分

| 层 | 问题 | 改造方案 |
|----|------|---------|
| **API Server** | device list/detail 接口硬编码提取 `ac.power` 等字段 | 改为根据 model_id 查询 device_model_field，动态构建返回字段 |
| **API Server** | protocol 表无管理接口 | 新增 protocol CRUD API |
| **Admin 网页** | 设备实时面板硬编码 + 控制按钮不生效 | 删除硬编码面板，用 DynamicFieldRenderer 替代；控制按钮对接真实命令 |
| **Admin 网页** | 无 protocol 管理页面 | 新增 protocol 管理 UI |
| **手机 App** | InverterRealtime 实体完全硬编码 | 改为通用 Map<String, dynamic> + 动态字段渲染 |
| **手机 App** | 控制页面 6 个固定命令 | 改为从 model field 的 is_control=true 动态读取 |
| **手机 App** | `_normalizeToNested` 100+ 行硬编码映射 | 删除，直接使用扁平 key-value |

---

## 实施方案（分 4 期）

### 第 1 期：API Server 改造（后端数据动态化）

**目标：** 设备列表和详情接口返回基于 model field 配置的动态字段

#### 1.1 设备列表接口改造
`device_handler.go` 的 `List` 方法：
- 现在：硬编码 `ac.power` → `CurrentPower`，`energy.daily_pv` → `DailyEnergy`
- 改为：查询设备的 model_id → 获取 device_model_field → 从 Redis 数据中提取 `is_show=true` 的字段 → 作为 `display_fields` 返回

```json
{
  "id": 1,
  "sn": "H1CNA00135000014",
  "model": "INV-5000-TL",
  "status": 1,
  "display_fields": {
    "ac_power": {"name": "交流功率", "value": 2319, "unit": "W"},
    "daily_pv": {"name": "今日发电", "value": 10.13, "unit": "kWh"},
    "batt_soc": {"name": "电池SOC", "value": 85, "unit": "%"}
  }
}
```

#### 1.2 设备详情接口改造
`GetDetail` 方法：
- 返回 `model_fields` 数组（包含 field_key, field_name, field_type, unit, is_show, is_control, sort）
- 返回 `realtime_data`（原始 Redis 数据，不做硬编码转换）
- 前端根据 model_fields 动态渲染

#### 1.3 Protocol 管理 API
新增 `model_handler.go` 端点：
- `GET /models/:id/protocols` — 获取型号的协议配置
- `POST /models/:id/protocols` — 创建协议配置
- `PUT /models/:id/protocols/:protocolId` — 更新协议配置
- `DELETE /models/:id/protocols/:protocolId` — 删除协议配置

#### 1.4 控制命令增强
`device_handler.go` 的 `Control` 方法：
- 现在：直接转发命令字符串
- 改为：根据 model field 的 `is_control=true` 验证命令合法性
- 新增 `control_fields` 端点：`GET /devices/:sn/control-fields` 返回该设备可用的控制命令列表

---

### 第 2 期：Admin 网页改造（管理界面动态化）

**目标：** 设备管理页面完全基于 model field 动态渲染

#### 2.1 删除硬编码实时面板
`devices/index.tsx` 的 `renderRealtimePanel`：
- 删除 AC/PV/battery/system 硬编码区块
- 用 `DynamicFieldRenderer` + `DynamicStatCards` 替代（已有组件）

#### 2.2 控制按钮对接真实命令
`devices/index.tsx` 的控制字段区域：
- 现在：点击"下发"只显示 toast
- 改为：调用 `POST /devices/:sn/control` 发送真实命令
- 新增命令参数输入框（根据 field_type 动态生成）

#### 2.3 Protocol 管理页面
新增 `models/:id/protocols` 页面：
- 列表显示 topic_pattern, parse_type, parse_config
- 支持增删改查
- parse_config 编辑器（JSON 编辑器或表单化）

#### 2.4 图表字段动态化
设备详情的遥测图表：
- 现在：硬编码提取 `power`, `voltage`, `current`
- 改为：让用户选择要显示的字段（从 model field 列表中选）

---

### 第 3 期：手机 App 改造（前端完全动态化）

**目标：** App 根据 model field 配置自动渲染设备数据和控制命令

#### 3.1 设备实时页面重写
`device_realtime_page.dart`：
- 删除 `_normalizeToNested` 函数（100+ 行硬编码映射）
- 删除 `_fallbackGroups` 硬编码分组
- 删除对 `InverterRealtime` 实体的依赖
- 改为：API 返回 `{realtime_data: {...}, model_fields: [...]}` → 按 field_key 分组渲染
- 分组策略：用 field_key 前缀（ac_, pv_, batt_, sys_, energy_）自动分组，或新增 `group` 字段到 device_model_field 表

#### 3.2 控制页面动态化
`device_control_page.dart`：
- 删除 6 个硬编码命令
- 改为：调用 `GET /devices/:sn/control-fields` 获取可用命令
- 根据 field_type 动态生成输入控件（数字输入、开关、下拉选择等）

#### 3.3 通用数据模型
替代 `InverterRealtime` 硬编码实体：
```dart
class DeviceRealtimeData {
  final String deviceSn;
  final bool online;
  final Map<String, FieldValue> fields; // field_key → value
  final List<ModelField> modelFields;   // 字段元数据
}

class FieldValue {
  final dynamic value;
  final String? unit;
  final DateTime? updatedAt;
}
```

#### 3.4 字段分组增强（可选）
在 `device_model_field` 表新增 `group` 字段：
```sql
ALTER TABLE device_model_field ADD COLUMN group_name VARCHAR(64) DEFAULT '';
```
- 管理页面配置字段所属分组（"交流参数"、"光伏参数"、"电池参数"等）
- App 和网页根据 group_name 分组显示
- 比前缀匹配更灵活

---

### 第 4 期：数据清理 + 完善

#### 4.1 清理遗留代码
- 删除 `device_models` 表的 `data_fields`、`field_mapping`、`mqtt_topics` JSONB 列
- 删除 device server 中读取这些旧列的代码
- 统一使用 `device_model_field` + `device_model_protocol` 表

#### 4.2 初始数据配置
为现有 INV-5000-TL 型号配置完整的：
- field 列表（所有需要显示/控制的字段）
- protocol 列表（data/ac, data/pv, data/energy, data/status, data/battery 等 topic 的解析规则）
- 控制命令（ac_on, ac_off, set_power_limit 等）

#### 4.3 新型号接入流程
标准化新型号接入步骤：
1. Admin 页面创建新型号
2. 配置 fields（显示字段 + 控制字段）
3. 配置 protocols（topic + 解析规则）
4. 绑定设备到型号
5. 设备自动开始按配置解析和显示数据

---

## 数据库变更

### 必须变更
```sql
-- 1. device_model_field 新增分组字段
ALTER TABLE device_model_field ADD COLUMN IF NOT EXISTS group_name VARCHAR(64) DEFAULT '';

-- 2. device_model_field 新增控制命令参数类型
ALTER TABLE device_model_field ADD COLUMN IF NOT EXISTS control_params JSONB DEFAULT '{}';
-- control_params 示例: {"min": 0, "max": 5000, "step": 100, "placeholder": "输入功率值(W)"}
```

### 可选变更
```sql
-- 3. devices 表确保 model_id 已关联
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model_id INT REFERENCES device_models(id);
UPDATE devices SET model_id = dm.id FROM device_models dm WHERE devices.model = dm.model_code AND devices.model_id IS NULL;
```

---

## 文件变更清单

### 第 1 期（后端）
| 文件 | 变更 |
|------|------|
| `inv_api_server/internal/handler/device_handler.go` | 改造 List/GetDetail 返回动态字段 |
| `inv_api_server/internal/handler/model_handler.go` | 新增 Protocol CRUD 端点 |
| `inv_api_server/internal/service/model_service.go` | 新增 Protocol 业务逻辑 |
| `inv_api_server/internal/repository/model_repository.go` | 新增 Protocol 查询 + 设备字段查询 |
| `inv_api_server/internal/model/models.go` | 新增 Protocol 结构体 |
| `inv_api_server/cmd/main.go` | 注册新路由 |

### 第 2 期（Admin 网页）
| 文件 | 变更 |
|------|------|
| `inv-admin-frontend/src/pages/devices/index.tsx` | 删除硬编码面板，控制按钮对接命令 |
| `inv-admin-frontend/src/pages/models/protocols.tsx` | 新增 protocol 管理页面 |
| `inv-admin-frontend/src/components/dyna/DynamicFieldRenderer.tsx` | 增强分组和控制支持 |
| `inv-admin-frontend/src/services/modelApi.ts` | 新增 protocol API 调用 |
| `inv-admin-frontend/src/services/deviceApi.ts` | 新增 control-fields API 调用 |

### 第 3 期（手机 App）
| 文件 | 变更 |
|------|------|
| `inv_app/lib/features/device/presentation/pages/device_realtime_page.dart` | 重写为全动态渲染 |
| `inv_app/lib/features/device/presentation/pages/device_control_page.dart` | 改为动态命令 |
| `inv_app/lib/core/entities/inverter_data.dart` | 替换为通用 DeviceRealtimeData |
| `inv_app/lib/features/device/data/datasources/device_remote_data_source.dart` | 新增 control-fields API |
| `inv_app/lib/features/device/presentation/bloc/device_bloc.dart` | 适配新数据结构 |

### 第 4 期（清理）
| 文件 | 变更 |
|------|------|
| `database/schema.sql` | 删除 device_models 旧 JSONB 列 |
| `inv_device_server/internal/repository/metadata_repository.go` | 移除旧列读取 |
| `deploy/create_device_models.sql` | 更新种子数据 |

---

## 实施顺序建议

```
第 1 期（后端）→ 第 2 期（Admin）→ 第 3 期（App）→ 第 4 期（清理）
   2-3 天           2-3 天           3-4 天          1 天
```

每一期独立可交付，不会互相阻塞。第 1 期做完后 Admin 网页的动态组件就能正常工作；第 2 期做完后管理界面完全动态化；第 3 期做完后 App 也完全动态化。
