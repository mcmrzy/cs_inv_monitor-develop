import { useState, useMemo, useCallback } from 'react'
import { Table, Button, Checkbox, Space, Popover, Input, Tooltip, Empty } from 'antd'
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table'
import { SettingOutlined, SearchOutlined, SortAscendingOutlined, SortDescendingOutlined } from '@ant-design/icons'

export interface FieldMeta {
  field_key: string
  field_name: string
  field_type: 'int' | 'float' | 'string' | 'bool'
  unit: string
  sort: number
  is_show: boolean
}

export interface DynamicTableProps<T extends Record<string, any>> {
  fields: FieldMeta[]
  dataSource: T[]
  loading?: boolean
  pagination?: TablePaginationConfig | false
  rowKey?: string | ((record: T) => string)
  onRow?: (record: T) => any
  className?: string
  scrollX?: number
}

const FIELD_TYPE_RENDER: Record<string, (val: any) => string> = {
  int: (v) => (v != null ? String(Math.round(v)) : '-'),
  float: (v) => (v != null ? (typeof v === 'number' ? v.toFixed(2) : String(v)) : '-'),
  string: (v) => (v != null ? String(v) : '-'),
  bool: (v) => (v === true ? '是' : v === false ? '否' : '-'),
}

function DynamicTable<T extends Record<string, any>>({
  fields,
  dataSource,
  loading = false,
  pagination = { pageSize: 20, showSizeChanger: true },
  rowKey = 'id',
  onRow,
  className,
  scrollX = 1200,
}: DynamicTableProps<T>) {
  const [visibleKeys, setVisibleKeys] = useState<Set<string>>(() => {
    const initial = fields.filter((f) => f.is_show).map((f) => f.field_key)
    return new Set(initial)
  })
  const [sortField, setSortField] = useState<string | null>(null)
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc')
  const [filters, setFilters] = useState<Record<string, string>>({})

  const toggleColumn = useCallback((key: string) => {
    setVisibleKeys((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }, [])

  const handleSort = useCallback((key: string) => {
    if (sortField === key) {
      setSortOrder((prev) => (prev === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortField(key)
      setSortOrder('asc')
    }
  }, [sortField])

  const sortedFields = useMemo(() => [...fields].sort((a, b) => a.sort - b.sort), [fields])

  const sortedData = useMemo(() => {
    if (!sortField) return dataSource
    return [...dataSource].sort((a, b) => {
      const va = a[sortField]
      const vb = b[sortField]
      if (va == null && vb == null) return 0
      if (va == null) return 1
      if (vb == null) return -1
      if (typeof va === 'number' && typeof vb === 'number') {
        return sortOrder === 'asc' ? va - vb : vb - va
      }
      const sa = String(va)
      const sb = String(vb)
      return sortOrder === 'asc' ? sa.localeCompare(sb) : sb.localeCompare(sa)
    })
  }, [dataSource, sortField, sortOrder])

  const filteredData = useMemo(() => {
    const filterKeys = Object.keys(filters).filter((k) => filters[k])
    if (filterKeys.length === 0) return sortedData
    return sortedData.filter((record) => {
      return filterKeys.every((key) => {
        const val = record[key]
        const filterVal = filters[key].toLowerCase()
        if (val == null) return false
        return String(val).toLowerCase().includes(filterVal)
      })
    })
  }, [sortedData, filters])

  const columns: ColumnsType<T> = useMemo(() => {
    return sortedFields
      .filter((f) => visibleKeys.has(f.field_key))
      .map((f) => ({
        title: (
          <Space size={4}>
            <span>{f.field_name}</span>
            <Tooltip title="排序">
              <Button
                type="text"
                size="small"
                icon={sortField === f.field_key
                  ? (sortOrder === 'asc' ? <SortAscendingOutlined style={{ color: '#1677ff' }} /> : <SortDescendingOutlined style={{ color: '#1677ff' }} />)
                  : <SortAscendingOutlined />}
                onClick={() => handleSort(f.field_key)}
              />
            </Tooltip>
          </Space>
        ),
        dataIndex: f.field_key,
        key: f.field_key,
        width: 140,
        ellipsis: true,
        sorter: undefined,
        render: (val: any) => {
          const formatted = FIELD_TYPE_RENDER[f.field_type]?.(val) ?? (val != null ? String(val) : '-')
          if (f.unit) {
            return <span>{formatted} <span style={{ color: '#999', fontSize: 12 }}>{f.unit}</span></span>
          }
          return formatted
        },
      }))
  }, [sortedFields, visibleKeys, sortField, sortOrder, handleSort])

  const columnSelector = (
    <div style={{ maxHeight: 300, overflow: 'auto', minWidth: 180 }}>
      {sortedFields.map((f) => (
        <div key={f.field_key} style={{ padding: '4px 0' }}>
          <Checkbox
            checked={visibleKeys.has(f.field_key)}
            onChange={() => toggleColumn(f.field_key)}
          >
            {f.field_name}
            <span style={{ color: '#999', fontSize: 12, marginLeft: 4 }}>{f.field_key}</span>
          </Checkbox>
        </div>
      ))}
      <div style={{ borderTop: '1px solid #f0f0f0', marginTop: 8, paddingTop: 8 }}>
        <Button size="small" onClick={() => setVisibleKeys(new Set(sortedFields.filter(f => f.is_show).map(f => f.field_key)))}>恢复默认</Button>
      </div>
    </div>
  )

  const filterRow = useMemo(() => {
    return (
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginBottom: 12, alignItems: 'center' }}>
        {sortedFields.slice(0, 6).map((f) => (
          <Input
            key={f.field_key}
            size="small"
            placeholder={`筛选${f.field_name}`}
            allowClear
            style={{ width: 120 }}
            value={filters[f.field_key] || ''}
            onChange={(e) => setFilters((prev) => ({ ...prev, [f.field_key]: e.target.value }))}
          />
        ))}
        <Popover content={columnSelector} title="选择显示列" trigger="click" placement="bottomRight">
          <Button size="small" icon={<SettingOutlined />}>列设置</Button>
        </Popover>
      </div>
    )
  }, [sortedFields, filters, columnSelector])

  if (fields.length === 0) {
    return <Empty description="无字段元数据，请先在型号管理中配置字段" />
  }

  return (
    <div className={className}>
      {filterRow}
      <Table<T>
        rowKey={rowKey}
        columns={columns}
        dataSource={filteredData}
        loading={loading}
        pagination={pagination}
        onRow={onRow}
        scroll={{ x: scrollX }}
        size="small"
        bordered
      />
    </div>
  )
}

export default DynamicTable
