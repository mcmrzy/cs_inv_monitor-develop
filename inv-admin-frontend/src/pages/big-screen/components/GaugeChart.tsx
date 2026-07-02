import React, { useMemo } from 'react';
import ReactECharts from 'echarts-for-react';
import type { EChartsOption } from 'echarts';

export interface GaugeChartProps {
  value: number;
  max?: number;
  label: string;
  color?: string;
  size?: number;
}

const GaugeChart: React.FC<GaugeChartProps> = ({
  value,
  max = 100,
  label,
  color = '#00d4ff',
  size = 120,
}) => {
  const percentage = Math.min((value / max) * 100, 100);

  const option = useMemo<EChartsOption>(
    () => ({
      series: [
        {
          type: 'gauge',
          startAngle: 200,
          endAngle: -20,
          min: 0,
          max: 100,
          radius: '90%',
          center: ['50%', '70%'],
          splitNumber: 5,
          axisLine: {
            lineStyle: {
              width: 10,
              color: [
                [0.3, '#ff4d4f'],
                [0.7, '#fa8c16'],
                [1, '#52c41a'],
              ],
            },
          },
          pointer: {
            icon: 'path://M12.8,0.7l12,40.1H0.7L12.8,0.7z',
            length: '55%',
            width: 6,
            offsetCenter: [0, '-10%'],
            itemStyle: {
              color,
              shadowColor: color,
              shadowBlur: 8,
            },
          },
          axisTick: {
            length: 4,
            lineStyle: { color: 'rgba(255,255,255,0.2)', width: 1 },
          },
          splitLine: {
            length: 8,
            lineStyle: { color: 'rgba(255,255,255,0.3)', width: 1 },
          },
          axisLabel: {
            color: 'rgba(255,255,255,0.4)',
            fontSize: 9,
            distance: -30,
          },
          title: {
            offsetCenter: [0, '20%'],
            fontSize: 11,
            color: '#aab',
          },
          detail: {
            fontSize: 20,
            fontWeight: 700,
            offsetCenter: [0, '-10%'],
            valueAnimation: true,
            formatter: '{value}%',
            color,
            textShadowColor: color,
            textShadowBlur: 10,
          },
          data: [{ value: parseFloat(percentage.toFixed(1)), name: label }],
        },
      ],
    }),
    [percentage, label, color],
  );

  return (
    <ReactECharts
      option={option}
      style={{ width: size, height: size * 0.7, margin: '0 auto' }}
      opts={{ renderer: 'canvas' }}
    />
  );
};

export default GaugeChart;
