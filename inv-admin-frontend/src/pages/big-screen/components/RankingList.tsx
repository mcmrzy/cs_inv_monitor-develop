import React from 'react';

export interface RankingItem {
  name: string;
  value: number;
  unit?: string;
}

export interface RankingListProps {
  items: RankingItem[];
  valueColor?: string;
  emptyText?: string;
}

const MEDAL_COLORS: Record<number, string> = {
  1: '#ffd700',
  2: '#c0c0c0',
  3: '#cd7f32',
};

const RankingList: React.FC<RankingListProps> = ({ items, valueColor = '#00d4ff', emptyText = '暂无数据' }) => {
  if (items.length === 0) {
    return <div className="bs-rank-empty">{emptyText}</div>;
  }

  const maxValue = Math.max(...items.map((i) => i.value), 1);

  return (
    <div className="bs-rank-list">
      {items.map((item, index) => {
        const rank = index + 1;
        const medalColor = MEDAL_COLORS[rank];
        const barPercent = (item.value / maxValue) * 100;

        return (
          <div key={item.name} className="bs-rank-item">
            <div
              className={`bs-rank-index ${rank <= 3 ? `bs-rank-index--${rank}` : ''}`}
            >
              {rank}
            </div>

            <div className="bs-rank-name" title={item.name}>
              {item.name}
            </div>

            <div className="bs-rank-bar">
              <div
                className="bs-rank-bar-fill"
                style={{
                  width: `${barPercent}%`,
                  background: medalColor
                    ? `linear-gradient(90deg, ${medalColor}88, ${medalColor})`
                    : undefined,
                }}
              />
            </div>

            <div className="bs-rank-value" style={{ color: valueColor }}>
              {item.value.toLocaleString()}
              {item.unit && <span style={{ fontSize: 10, marginLeft: 2 }}>{item.unit}</span>}
            </div>
          </div>
        );
      })}
    </div>
  );
};

export default RankingList;
