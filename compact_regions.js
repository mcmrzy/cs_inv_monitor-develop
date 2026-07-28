const fs = require('fs');
const src = fs.readFileSync('inv-admin-frontend/src/utils/regionData.ts', 'utf8');
// Extract the array between 'const regionData: RegionOption[] = [' and the closing '];'
const startIdx = src.indexOf('const regionData');
const eqIdx = src.indexOf('=', startIdx);
const arrStart = src.indexOf('[', eqIdx);
// Find the matching closing bracket
let depth = 0, endIdx = arrStart;
for (let i = arrStart; i < src.length; i++) {
  if (src[i] === '[') depth++;
  else if (src[i] === ']') { depth--; if (depth === 0) { endIdx = i; break; } }
}
const arrStr = src.slice(arrStart, endIdx + 1);
const data = eval(arrStr);

// Compact: if value === label and no children, just use string
function compact(arr) {
  return arr.map(n => {
    if (!n.children || n.children.length === 0) return n.value;
    return { name: n.value, children: compact(n.children) };
  });
}

const c = compact(data);

const out = `// Auto-generated compact region data
export interface RegionNode { name: string; children?: RegionNode[] }
function toOpts(nodes: (string | RegionNode)[]): any[] {
  return nodes.map(n => {
    if (typeof n === 'string') return { value: n, label: n };
    const children = n.children ? toOpts(n.children) : undefined;
    return { value: n.name, label: n.name, children };
  });
}
const raw: (string | RegionNode)[] = ${JSON.stringify(c)};
const regionData = toOpts(raw);
export default regionData;
`;

fs.writeFileSync('inv-admin-frontend/src/utils/regionData.ts', out);
console.log('Done, size:', Buffer.byteLength(out), 'bytes');
