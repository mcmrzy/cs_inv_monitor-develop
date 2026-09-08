import { ProTable } from '@ant-design/pro-components'
import type { ProColumns, ProTableProps } from '@ant-design/pro-components'
import type { ColumnsType } from 'antd/es/table'

/**
 * 列表页统一表格：基于 ProTable 的受控数据源封装。
 *
 * 统一 ota/stations 已有的表格工具栏体验（密度/刷新/列设置），
 * 供 alerts/users/operation-logs 等裸 Table 列表页迁移复用：
 *
 * - 固定 search=false：筛选由页面自带的自定义筛选区负责，不启用 ProTable 查询表单
 * - 固定 options={{ density, reload, setting }}：工具栏统一，onReload 缺省保留默认行为
 * - 列设置按 persistenceKey 持久化到 localStorage，刷新/重进页面保留列偏好
 * - 不使用 request 模式：数据仍由页面 react-query 拉取，以受控 dataSource/total
 *   传入（pagination 透传 antd Table 配置），避免重写既有数据层
 *
 * 列定义沿用 antd ColumnsType，页面平移时无需改写为 ProColumns。
 */
export interface ListPageTableProps<RecordType extends object = any>
  extends Omit<
    ProTableProps<RecordType, any>,
    'request' | 'search' | 'options' | 'columnsState' | 'columns'
  > {
  /** 列定义（与 antd Table 列一致） */
  columns: ColumnsType<RecordType>
  /** 列设置持久化键（页面内唯一，如 'alerts-list'） */
  persistenceKey: string
  /** 工具栏刷新按钮回调（如 react-query 的 refetch）；缺省时保留 ProTable 默认行为 */
  onReload?: () => void
}

type AnyColumn = Record<string, any>

/**
 * antd Table 与 ProTable 的列 render 首参语义不同：
 * antd 传原始字段值（text），ProTable 传默认渲染后的 DOM 节点。
 * 这里把原始字段值重新作为首参传给页面列定义（entity 仍作第二参），
 * 保证既有列定义从裸 Table 平移到 ProTable 时渲染逻辑零改动。
 */
function toProColumns<RecordType extends object>(
  columns: ColumnsType<RecordType>,
): ProColumns<RecordType>[] {
  return (columns as AnyColumn[]).map((column) => {
    const dataIndex = Array.isArray(column.dataIndex)
      ? column.dataIndex.join('.')
      : column.dataIndex
    if (typeof column.render !== 'function' || typeof dataIndex !== 'string') {
      return column as unknown as ProColumns<RecordType>
    }
    const originalRender = column.render
    return {
      ...column,
      render: (_dom: any, entity: RecordType, index: number, ...rest: any[]) =>
        originalRender(
          (entity as AnyColumn | undefined)?.[dataIndex],
          entity,
          index,
          ...rest,
        ),
    } as unknown as ProColumns<RecordType>
  })
}

function ListPageTable<RecordType extends object = any>({
  columns,
  persistenceKey,
  onReload,
  ghost = true,
  ...rest
}: ListPageTableProps<RecordType>) {
  return (
    <ProTable<RecordType, any>
      search={false}
      options={{ density: true, reload: onReload ?? true, setting: true }}
      columnsState={{ persistenceKey, persistenceType: 'localStorage' }}
      columns={toProColumns(columns)}
      ghost={ghost}
      {...rest}
    />
  )
}

export default ListPageTable
