import React from 'react';
import { ArrowUpOutlined, ArrowDownOutlined } from '@ant-design/icons';

export interface StatCardProps {
  icon: React.ReactNode;
  label: string;
  value: string | number;
  unit?: string;
  color: string;
  trend?: { value: number; isUp: boolean };
}

const StatCard: React.FC<StatCardProps> = ({ icon, label, value, unit, color, trend }) => {
  return (
    <div className="bs-stat-card bs-animate-fade-in">
      <div
        className="bs-stat-icon"
        style={{
          background: `radial-gradient(circle, ${color}33 0%, ${color}11 70%)`,
          color,
          boxShadow: `0 0 12px ${color}44`,
        }}
      >
        {icon}
      </div>

      <div className="bs-stat-content">
        <div className="bs-stat-label">{label}</div>
        <div className="bs-stat-value-row">
          <span className="bs-stat-value" style={{ color }}>
            {value}
          </span>
          {unit && <span className="bs-stat-unit">{unit}</span>}
        </div>
      </div>

      {trend && (
        <div className={`bs-stat-trend ${trend.isUp ? 'bs-stat-trend--up' : 'bs-stat-trend--down'}`}>
          {trend.isUp ? <ArrowUpOutlined /> : <ArrowDownOutlined />}
          <span>{Math.abs(trend.value).toFixed(1)}%</span>
        </div>
      )}
    </div>
  );
};

export default StatCard;
