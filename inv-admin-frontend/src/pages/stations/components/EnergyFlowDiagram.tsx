import React, { useMemo } from 'react';

interface EnergyFlowDiagramProps {
  pvPower: number;
  loadPower: number;
  battPower: number;
  gridPower: number;
  battSoc: number;
}

interface FlowEdge {
  id: string;
  path: string;
  color: string;
  active: boolean;
  power: number;
  markerId: string;
}

interface NodeConfig {
  type: string;
  x: number;
  y: number;
  color: string;
  icon: string;
  label: string;
}

const NODE_COLORS: Record<string, string> = {
  pv: '#F59E0B',
  battery: '#22C55E',
  inverter: '#8B5CF6',
  grid: '#94A3B8',
  load: '#3B82F6',
};

const NODES: NodeConfig[] = [
  { type: 'pv', x: 300, y: 60, color: NODE_COLORS.pv, icon: '☀️', label: '光伏' },
  { type: 'battery', x: 80, y: 250, color: NODE_COLORS.battery, icon: '🔋', label: '电池' },
  { type: 'inverter', x: 300, y: 250, color: NODE_COLORS.inverter, icon: '⚡', label: '逆变器' },
  { type: 'grid', x: 520, y: 250, color: NODE_COLORS.grid, icon: '🔌', label: '电网' },
  { type: 'load', x: 300, y: 440, color: NODE_COLORS.load, icon: '💡', label: '负载' },
];

function formatPower(w: number): string {
  const abs = Math.abs(w);
  if (abs >= 1000) return `${(abs / 1000).toFixed(1)}kW`;
  return `${abs.toFixed(0)}W`;
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
): FlowEdge[] {
  const edges: FlowEdge[] = [];

  // 1. PV → Inverter (straight down)
  edges.push({
    id: 'pv-inv',
    path: 'M 300 100 L 300 210',
    color: NODE_COLORS.pv,
    active: pvPower > 0,
    power: pvPower,
    markerId: 'arrow-pv',
  });

  // 2. Inverter → Load (straight down)
  edges.push({
    id: 'inv-load',
    path: 'M 300 290 L 300 400',
    color: NODE_COLORS.inverter,
    active: loadPower > 0,
    power: loadPower,
    markerId: 'arrow-inv',
  });

  // 3. PV → Battery (curve, upper-left) — charging
  edges.push({
    id: 'pv-batt',
    path: 'M 270 80 Q 160 120 110 210',
    color: NODE_COLORS.battery,
    active: pvPower > 0 && battPower > 0,
    power: battPower > 0 ? battPower : 0,
    markerId: 'arrow-batt',
  });

  // 4. Battery → Inverter (curve, left-center) — discharging
  edges.push({
    id: 'batt-inv',
    path: 'M 120 250 Q 180 280 260 260',
    color: NODE_COLORS.battery,
    active: battPower < 0,
    power: battPower < 0 ? Math.abs(battPower) : 0,
    markerId: 'arrow-batt',
  });

  // 5. Grid → Inverter (straight, right to center) — consuming
  edges.push({
    id: 'grid-inv',
    path: 'M 480 250 L 340 250',
    color: NODE_COLORS.grid,
    active: gridPower > 0,
    power: gridPower,
    markerId: 'arrow-grid',
  });

  // 6. Inverter → Grid (straight, center to right) — feeding
  edges.push({
    id: 'inv-grid',
    path: 'M 340 260 L 480 260',
    color: NODE_COLORS.inverter,
    active: gridPower < 0,
    power: gridPower < 0 ? Math.abs(gridPower) : 0,
    markerId: 'arrow-inv',
  });

  return edges;
}

const svgAnimations = `
  @keyframes pulse {
    0%, 100% { r: 40; opacity: 0.3; }
    50% { r: 48; opacity: 0.1; }
  }
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
  .node-pulse {
    animation: pulse 2.5s ease-in-out infinite;
  }
`;

const FlowNode: React.FC<{
  node: NodeConfig;
  power: number;
  extra?: string;
}> = React.memo(({ node, power, extra }) => {
  const { x, y, color, icon, label, type } = node;
  const displayPower = type === 'battery' && power < 0 ? Math.abs(power) : power;

  return (
    <g>
      {/* Pulse ring */}
      <circle
        cx={x}
        cy={y}
        r={40}
        fill={color}
        opacity={0.3}
        className="node-pulse"
      />
      {/* Main circle */}
      <circle cx={x} cy={y} r={35} fill={color} />
      {/* Icon / Image */}
      {type === 'battery' ? (
        <image
          href="/images/energy-flow/battery.jpg"
          x={x - 28}
          y={y - 28}
          width={56}
          height={56}
          clipPath="url(#circle-clip-batt)"
          preserveAspectRatio="xMidYMid slice"
        />
      ) : (
        <text
          x={x}
          y={y - 8}
          textAnchor="middle"
          dominantBaseline="central"
          fill="#fff"
          fontSize="18"
        >
          {icon}
        </text>
      )}
      {/* Label */}
      <text
        x={x}
        y={y + 10}
        textAnchor="middle"
        dominantBaseline="central"
        fill="#fff"
        fontSize="9"
        fontWeight="500"
      >
        {label}
      </text>
      {/* Power value below node */}
      <text
        x={x}
        y={y + 52}
        textAnchor="middle"
        dominantBaseline="central"
        fill="#64748b"
        fontSize="12"
        fontWeight="600"
      >
        {formatPower(displayPower)}
      </text>
      {/* Extra info (SOC) */}
      {extra && (
        <text
          x={x}
          y={y + 66}
          textAnchor="middle"
          dominantBaseline="central"
          fill="#94a3b8"
          fontSize="11"
        >
          {extra}
        </text>
      )}
    </g>
  );
});

FlowNode.displayName = 'FlowNode';

const FlowPath: React.FC<{ edge: FlowEdge }> = React.memo(({ edge }) => {
  const sw = calcStrokeWidth(edge.power);

  return (
    <path
      d={edge.path}
      fill="none"
      stroke={edge.color}
      strokeWidth={sw}
      strokeLinecap="round"
      markerEnd={edge.active ? `url(#${edge.markerId})` : undefined}
      className={edge.active ? 'flow-path-active' : 'flow-path-inactive'}
      style={edge.active ? { opacity: 0.8 } : undefined}
    />
  );
});

FlowPath.displayName = 'FlowPath';

const EnergyFlowDiagram: React.FC<EnergyFlowDiagramProps> = ({
  pvPower,
  loadPower,
  battPower,
  gridPower,
  battSoc,
}) => {
  const edges = useMemo(
    () => computeFlowEdges(pvPower, loadPower, battPower, gridPower),
    [pvPower, loadPower, battPower, gridPower],
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
      (battPower < 0 ? Math.abs(battPower) : 0) +
      (gridPower > 0 ? gridPower : 0);
    return sources;
  }, [pvPower, battPower, gridPower]);

  return (
    <div style={{ width: '100%', maxWidth: 600, margin: '0 auto' }}>
      <svg
        viewBox="0 0 600 500"
        style={{ width: '100%', height: 'auto', display: 'block' }}
        xmlns="http://www.w3.org/2000/svg"
      >
        <style>{svgAnimations}</style>
        <defs>
          {markerDefs}
          <clipPath id="circle-clip-batt">
            <circle cx={80} cy={250} r={28} />
          </clipPath>
        </defs>

        {/* Background grid (subtle) */}
        <rect width="600" height="500" fill="transparent" rx="12" />

        {/* Flow paths (rendered behind nodes) */}
        {edges.map((edge) => (
          <FlowPath key={edge.id} edge={edge} />
        ))}

        {/* Nodes */}
        {NODES.map((node) => {
          let power = 0;
          let extra: string | undefined;

          switch (node.type) {
            case 'pv':
              power = pvPower;
              break;
            case 'battery':
              power = battPower;
              extra = `${battSoc}%`;
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
