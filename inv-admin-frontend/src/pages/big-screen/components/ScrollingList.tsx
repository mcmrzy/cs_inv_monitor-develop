import React from 'react';

export interface ScrollingListProps<T> {
  items: T[];
  renderItem: (item: T, index: number) => React.ReactNode;
  speed?: number;
  itemHeight?: number;
  emptyText?: string;
}

function ScrollingList<T>({
  items,
  renderItem,
  speed = 20,
  itemHeight: _itemHeight = 50,
  emptyText = '暂无数据',
}: ScrollingListProps<T>): React.ReactElement {
  const duration = speed;

  if (items.length === 0) {
    return (
      <div className="bs-alert-scroll">
        <div className="bs-alert-empty">{emptyText}</div>
      </div>
    );
  }

  return (
    <div className="bs-alert-scroll">
      <div
        className="bs-alert-scroll-inner"
        style={{ animationDuration: `${duration}s` }}
      >
        {items.map((item, i) => (
          <React.Fragment key={`a-${i}`}>{renderItem(item, i)}</React.Fragment>
        ))}
        {items.map((item, i) => (
          <React.Fragment key={`b-${i}`}>{renderItem(item, i)}</React.Fragment>
        ))}
      </div>
    </div>
  );
}

export default ScrollingList;
