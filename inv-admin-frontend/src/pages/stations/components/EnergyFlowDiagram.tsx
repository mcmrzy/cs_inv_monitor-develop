import React, { useMemo } from 'react';
import useTranslation from '@/hooks/useTranslation';
import type { SysStatusBits } from '@/pages/device-detail/energyUtils';

interface EnergyFlowDiagramProps {
  pvPower: number;
  loadPower: number;
  battPower: number;
  gridPower: number;
  battSoc: number;
  // 发电机功率（可选：CS-L10-6K2 等带发电机输入的型号上报时有值，否则路径隐藏）
  genPower?: number;
  // sys_status 12 位状态位（可选，V2 设备）：传入时流动动画由状态位驱动；
  // 未传入时维持原功率正负驱动逻辑（电站页等现有调用方零改动）
  sysBits?: SysStatusBits | null;
}

interface FlowEdge {
  id: string;
  path: string;
  color: string;
  active: boolean;
  power: number;
  markerId: string;
  noArrows?: boolean;
}

interface NodeConfig {
  type: string;
  x: number;
  y: number;
  color: string;
  label: string;
  image: string;
  posCategory?: 'top' | 'right' | 'bottom' | 'topright';
}

const NODE_COLORS: Record<string, string> = {
  pv: '#F59E0B',
  battery: '#22C55E',
  inverter: '#8B5CF6',
  grid: '#94A3B8',
  load: '#3B82F6',
  gen: '#F97316',
};

const getNodes = (t: (key: string) => string): NodeConfig[] => [
  { type: 'gen', x: 100, y: 85, color: NODE_COLORS.gen, label: t('station.genNode'), image: '/images/energy-flow/gen.png' },
  { type: 'pv', x: 300, y: 85, color: NODE_COLORS.pv, label: t('station.pv'), image: '/images/energy-flow/pv.jpg' },
  { type: 'battery', x: 80, y: 275, color: NODE_COLORS.battery, label: t('station.battery'), image: '/images/energy-flow/battery.jpg' },
  { type: 'inverter', x: 300, y: 275, color: NODE_COLORS.inverter, label: t('station.inverter'), image: '/images/energy-flow/inverter.png' },
  { type: 'grid', x: 520, y: 275, color: NODE_COLORS.grid, label: t('station.grid'), image: '/images/energy-flow/grid.jpg' },
  { type: 'load', x: 300, y: 465, color: NODE_COLORS.load, label: t('station.load'), image: '/images/energy-flow/load.jpg' },
];

function formatPower(w: number): string {
  const abs = Math.abs(Math.round(w));
  if (abs >= 1000) return `${(abs / 1000).toFixed(1)}kW`;
  return `${abs}W`;
}

function calcStrokeWidth(power: number): number {
  if (power <= 0) return 2;
  const maxExpected = 5000;
  const ratio = Math.min(power / maxExpected, 1);
  return 2 + ratio * 4;
}

function computeFlowEdges(
  pvPower: number,
  loadPower: number,
  battPower: number,
  gridPower: number,
  genPower = 0,
  sysBits?: SysStatusBits | null,
): FlowEdge[] {
  const edges: FlowEdge[] = [];
  // 位驱动安全阈值：位为 true 但对应功率≈ 0 时不点亮动画（防位残留误动画）
  const MIN_FLOW_W = 5;
  // 位驱动：bit 且功率超阈值；无 bits 时保持原功率正负判定（>0）
  const bitOn = (bit: boolean | undefined, power: number) =>
    sysBits ? Boolean(bit) && power > MIN_FLOW_W : power > 0;

  // 0. Generator → Inverter (curve, upper-left) — only when gen power data exists
  if (genPower > 0 || sysBits?.geInput) {
    edges.push({
      id: 'gen-inv',
      path: 'M 150 135 C 150 225, 200 240, 250 240',
      color: NODE_COLORS.gen,
      active: bitOn(sysBits?.geInput ?? genPower > 0, genPower),
      power: genPower,
      markerId: 'arrow-gen',
    });
  }

  // 1. PV → Inverter (straight down) — no static arrowhead marker
  edges.push({
    id: 'pv-inv',
    path: 'M 300 135 L 300 225',
    color: NODE_COLORS.pv,
    active: bitOn(sysBits?.pvInput ?? pvPower > 0, pvPower),
    power: pvPower,
    markerId: 'arrow-pv',
    noArrows: true, // 禁用末端静态大箭头，保留流动动画
  });

  // 2. Inverter → Load (straight down)
  edges.push({
    id: 'inv-load',
    path: 'M 300 325 L 300 415',
    color: NODE_COLORS.inverter,
    active: bitOn(sysBits?.toLoad ?? loadPower > 0, loadPower),
    power: loadPower,
    markerId: 'arrow-inv',
  });

  // 3. Inverter → Battery (curve, left-upper) — charging via inverter
  edges.push({
    id: 'inv-batt',
    path: 'M 250 265 L 130 265',
    color: NODE_COLORS.battery,
    active: bitOn(sysBits?.charge ?? battPower > 0, battPower > 0 ? battPower : 0),
    power: battPower > 0 ? battPower : 0,
    markerId: 'arrow-batt',
  });

  // 4. Battery → Inverter (curve, left-lower) — discharging via inverter
  const disW = battPower < 0 ? Math.abs(battPower) : 0;
  edges.push({
    id: 'batt-inv',
    path: 'M 130 285 L 250 285',
    color: NODE_COLORS.battery,
    active: bitOn(sysBits?.discharge ?? battPower < 0, disW),
    power: disW,
    markerId: 'arrow-batt',
  });

  // 5. Grid → Inverter (straight, right to center) — consuming
  edges.push({
    id: 'grid-inv',
    path: 'M 470 265 L 350 265',
    color: NODE_COLORS.grid,
    active: bitOn(sysBits?.acInput ?? gridPower > 0, gridPower > 0 ? gridPower : 0),
    power: gridPower > 0 ? gridPower : 0,
    markerId: 'arrow-grid',
  });

  // 6. Inverter → Grid (straight, center to right) — feeding
  // 无专用状态位（协议未定义馈电位），始终按功率方向驱动
  edges.push({
    id: 'inv-grid',
    path: 'M 350 285 L 470 285',
    color: NODE_COLORS.inverter,
    active: gridPower < 0 && Math.abs(gridPower) > 0,
    power: gridPower < 0 ? Math.abs(gridPower) : 0,
    markerId: 'arrow-inv',
  });

  return edges;
}

const svgAnimations = `
  @keyframes flow {
    from { stroke-dashoffset: 0; }
    to { stroke-dashoffset: -20; }
  }
  .flow-path-active {
    stroke-dasharray: 8 12;
    animation: flow 1s linear infinite;
  }
  .flow-path-inactive {
    stroke-dasharray: 4 8;
    opacity: 0.15;
  }
`;

const FlowNode: React.FC<{
  node: NodeConfig;
  power: number;
  extra?: string;
}> = React.memo(({ node, power, extra }) => {
  const { x, y, label, type, image } = node;
  const displayPower = type === 'battery' && power < 0 ? Math.abs(power) : power;

  const imgSize = 100;
  // Position category: 'top' = text above (battery/grid), 'topright' = text top-right (inverter), 'right' = text right (pv/load)
  const posCategory: 'top' | 'right' | 'bottom' | 'topright' = type === 'inverter' ? 'topright'
    : (type === 'battery' || type === 'grid' ? 'top' : 'right');

  // Image edges
  const imgTop = y - imgSize / 2;   // y - 50
  const imgRight = x + imgSize / 2; // x + 50

  // Gaps
  const topGap = 5;   // px between text baseline and image top edge

  return (
    <g>
      {/* Node image */}
      <image
        href={image}
        x={x - imgSize / 2}
        y={y - imgSize / 2}
        width={imgSize}
        height={imgSize}
        preserveAspectRatio="xMidYMid meet"
        rx={10}
      />

      {posCategory === 'top' ? (
        <>
          {/* Power value: tightly above image top */}
          <text
            x={x}
            y={imgTop - topGap}
            textAnchor="middle"
            dominantBaseline="auto"
            fill="#555"
            fontSize="12"
            fontWeight="600"
            style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
          >
            {formatPower(displayPower)}
          </text>
          {/* Label: above power text */}
          <text
            x={x}
            y={imgTop - topGap - 17}
            textAnchor="middle"
            dominantBaseline="auto"
            fill="#333"
            fontSize="13"
            fontWeight="700"
            style={{ textShadow: '0 0 4px rgba(255,255,255,0.9), 0 0 8px rgba(255,255,255,0.7)' }}
          >
            {label}
          </text>
          {/* Extra info (SOC): above label */}
          {extra && (
            <text
              x={x}
              y={imgTop - topGap - 34}
              textAnchor="middle"
              dominantBaseline="auto"
              fill="#555"
              fontSize="12"
              fontWeight="500"
              style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
            >
              {extra}
            </text>
          )}
        </>
      ) : posCategory === 'right' ? (
        <>
          {/* Label: right of image */}
          <text
            x={imgRight + 4}
            y={y - 6}
            textAnchor="start"
            dominantBaseline="central"
            fill="#333"
            fontSize="13"
            fontWeight="700"
            style={{ textShadow: '0 0 4px rgba(255,255,255,0.9), 0 0 8px rgba(255,255,255,0.7)' }}
          >
            {label}
          </text>
          {/* Power value: right of image, below label */}
          <text
            x={imgRight + 4}
            y={y + 10}
            textAnchor="start"
            dominantBaseline="central"
            fill="#555"
            fontSize="12"
            fontWeight="600"
            style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
          >
            {formatPower(displayPower)}
          </text>
          {/* Extra info below image (not expected for right-side nodes) */}
          {extra && (
            <text
              x={x}
              y={y + imgSize / 2 + 16}
              textAnchor="middle"
              dominantBaseline="auto"
              fill="#555"
              fontSize="12"
              fontWeight="500"
              style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
            >
              {extra}
            </text>
          )}
        </>
      ) : null}
      {posCategory === 'topright' && (
        <>
          {/* Label: top-right corner of image */}
          <text
            x={imgRight + 4}
            y={imgTop + 8}
            textAnchor="start"
            dominantBaseline="auto"
            fill="#333"
            fontSize="13"
            fontWeight="700"
            style={{ textShadow: '0 0 4px rgba(255,255,255,0.9), 0 0 8px rgba(255,255,255,0.7)' }}
          >
            {label}
          </text>
          {/* Power value: below label */}
          <text
            x={imgRight + 4}
            y={imgTop + 24}
            textAnchor="start"
            dominantBaseline="auto"
            fill="#555"
            fontSize="12"
            fontWeight="600"
            style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
          >
            {formatPower(displayPower)}
          </text>
          {extra && (
            <text
              x={imgRight + 4}
              y={imgTop + 40}
              textAnchor="start"
              dominantBaseline="auto"
              fill="#555"
              fontSize="12"
              fontWeight="500"
              style={{ textShadow: '0 0 3px rgba(255,255,255,0.8)' }}
            >
              {extra}
            </text>
          )}
        </>
      )}
    </g>
  );
});

FlowNode.displayName = 'FlowNode';

const FlowPath: React.FC<{ edge: FlowEdge }> = React.memo(({ edge }) => {
  const sw = calcStrokeWidth(edge.power);

  return (
    <path
      id={edge.id}
      d={edge.path}
      fill="none"
      stroke={edge.color}
      strokeWidth={sw}
      strokeLinecap="round"
      markerEnd={edge.active && !edge.noArrows ? `url(#${edge.markerId})` : undefined}
      className={edge.active ? 'flow-path-active' : 'flow-path-inactive'}
      style={edge.active ? { opacity: 0.8 } : undefined}
    />
  );
});

FlowPath.displayName = 'FlowPath';

const FlowArrows: React.FC<{ edge: FlowEdge }> = React.memo(({ edge }) => {
  if (!edge.active) return null;
  const N = 3;
  const dur = 1.8;
  return (
    <g>
      {Array.from({ length: N }).map((_, i) => (
        <g key={i}>
          <polygon
            points="-6,-4 6,0 -6,4"
            fill={edge.color}
            opacity={0}
          >
            <animateMotion
              dur={`${dur}s`}
              repeatCount="indefinite"
              begin={`${(i * dur) / N}s`}
              rotate="auto"
            >
              <mpath href={`#${edge.id}`} />
            </animateMotion>
            <animate
              attributeName="opacity"
              values="0;0.9;0.9;0"
              keyTimes="0;0.15;0.85;1"
              dur={`${dur}s`}
              repeatCount="indefinite"
              begin={`${(i * dur) / N}s`}
            />
          </polygon>
        </g>
      ))}
    </g>
  );
});

FlowArrows.displayName = 'FlowArrows';

const EnergyFlowDiagram: React.FC<EnergyFlowDiagramProps> = ({
  pvPower,
  loadPower,
  battPower,
  gridPower,
  battSoc,
  genPower = 0,
  sysBits = null,
}) => {
  const { t } = useTranslation();
  const NODES = useMemo(() => getNodes(t), [t]);

  const edges = useMemo(
    () => computeFlowEdges(pvPower, loadPower, battPower, gridPower, genPower, sysBits),
    [pvPower, loadPower, battPower, gridPower, genPower, sysBits],
  );

  const markerDefs = useMemo(
    () =>
      Object.entries(NODE_COLORS).map(([key, color]) => (
        <marker
          key={`arrow-${key}`}
          id={`arrow-${key}`}
          viewBox="0 0 10 10"
          refX="8"
          refY="5"
          markerWidth="6"
          markerHeight="6"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={color} />
        </marker>
      )),
    [],
  );

  const inverterPower = useMemo(() => {
    const sources =
      Math.max(pvPower, 0) +
      Math.max(genPower, 0) +
      (battPower < 0 ? Math.abs(battPower) : 0) +
      (gridPower > 0 ? gridPower : 0);
    return sources;
  }, [pvPower, genPower, battPower, gridPower]);

  return (
    <div style={{ width: '100%', maxWidth: 600, margin: '0 auto' }}>
      <svg
        viewBox="0 0 600 540"
        style={{ width: '100%', height: 'auto', display: 'block' }}
        xmlns="http://www.w3.org/2000/svg"
      >
        <style>{svgAnimations}</style>
        <defs>
          {markerDefs}
        </defs>

        {/* Background grid (subtle) */}
        <rect width="600" height="540" fill="transparent" rx="12" />

        {/* Flow paths (rendered behind nodes) */}
        {edges.map((edge) => (
          <FlowPath key={edge.id} edge={edge} />
        ))}

        {/* Animated flow arrows */}
        {edges.map((edge) => (
          <FlowArrows key={`arrows-${edge.id}`} edge={edge} />
        ))}

        {/* Nodes */}
        {NODES.map((node) => {
          let power = 0;
          let extra: string | undefined;

          switch (node.type) {
            case 'gen':
              power = genPower;
              break;
            case 'pv':
              power = pvPower;
              break;
            case 'battery':
              power = battPower;
              if (battPower > 0) {
                extra = `${Math.round(battSoc)}% ${t('station.charging') || '充电中'}`;
              } else if (battPower < 0) {
                extra = `${Math.round(battSoc)}% ${t('station.discharging') || '放电中'}`;
              } else {
                extra = `${Math.round(battSoc)}%`;
              }
              break;
            case 'inverter':
              power = inverterPower;
              break;
            case 'grid':
              power = gridPower;
              break;
            case 'load':
              power = loadPower;
              break;
          }

          return <FlowNode key={node.type} node={node} power={power} extra={extra} />;
        })}
      </svg>
    </div>
  );
};

export default EnergyFlowDiagram;
