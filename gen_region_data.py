#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Generate compact regionData.ts from mobile app's region data."""
import re
import json
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ---- Parse china_regions.dart ----
with open('inv_app/lib/core/data/china_regions.dart', 'r', encoding='utf-8') as f:
    china_content = f.read()

# Parse countries list
COUNTRY_CODE_MAP = {}
EN_TO_CN = {}
for m in re.finditer(r"\{'code': '([^']+)', 'name': '([^']+)'\},?\s*//\s*(.+)", china_content):
    code, name_cn, name_en = m.groups()
    COUNTRY_CODE_MAP[name_cn] = code
    EN_TO_CN[name_en.strip()] = name_cn

# Parse chinaRegions map: extract province -> city -> [districts]
china_data = {}
# Find the addAll block
addall_match = re.search(r'chinaRegions\.addAll\(\{(.*?)\}\);', china_content, re.DOTALL)
if addall_match:
    block = addall_match.group(1)
    # Split by province keys: 'province_name': {
    prov_pattern = re.compile(r"'([^']+)':\s*\{")
    provinces = list(prov_pattern.finditer(block))
    
    for i, pm in enumerate(provinces):
        prov_name = pm.group(1)
        start = pm.end()
        end = provinces[i + 1].start() if i + 1 < len(provinces) else len(block)
        prov_block = block[start:end]
        
        china_data[prov_name] = {}
        # Split by city keys: 'city_name': [
        city_pattern = re.compile(r"'([^']+)':\s*\[")
        cities = list(city_pattern.finditer(prov_block))
        
        for j, cm in enumerate(cities):
            city_name = cm.group(1)
            cstart = cm.end()
            cend = cities[j + 1].start() if j + 1 < len(cities) else len(prov_block)
            city_block = prov_block[cstart:cend]
            
            # Extract district names
            districts = re.findall(r"'([^']+)'", city_block)
            china_data[prov_name][city_name] = districts

print(f"Parsed China data: {len(china_data)} provinces")

# ---- Parse regions_data.dart ----
with open('inv_app/lib/core/data/regions_data.dart', 'r', encoding='utf-8') as f:
    global_content = f.read()

global_regions = {}
addall_match = re.search(r'globalRegions\.addAll\(\{(.*?)\}\);', global_content, re.DOTALL)
if addall_match:
    block = addall_match.group(1)
    # Country keys: 'CountryName': [
    country_pattern = re.compile(r"'((?:[^'\\]|\\.)+)':\s*\[")
    countries_found = list(country_pattern.finditer(block))
    
    for i, cm in enumerate(countries_found):
        country_name = cm.group(1)
        start = cm.end()
        end = countries_found[i + 1].start() if i + 1 < len(countries_found) else len(block)
        country_block = block[start:end]
        
        # Extract province/state names
        provinces = re.findall(r"'((?:[^'\\]|\\.)+)'", country_block)
        global_regions[country_name] = provinces

print(f"Parsed global regions: {len(global_regions)} countries")

# ---- Build compact data structure ----
data = []

# China with full hierarchy
china_node = {"name": "中国", "children": []}
for province in sorted(china_data.keys()):
    cities = china_data[province]
    prov_node = {"name": province, "children": []}
    for city in sorted(cities.keys()):
        districts = cities[city]
        if len(districts) > 0:
            city_node = {"name": city, "children": sorted(districts)}
            prov_node["children"].append(city_node)
        else:
            prov_node["children"].append(city)
    china_node["children"].append(prov_node)
data.append(china_node)

# Other countries (province level only)
sorted_countries = sorted(global_regions.items(), key=lambda x: EN_TO_CN.get(x[0], x[0]))
for country_en, provinces in sorted_countries:
    if country_en == 'China':
        continue
    country_cn = EN_TO_CN.get(country_en, country_en)
    if not provinces:
        continue
    data.append({"name": country_cn, "children": sorted(provinces)})

# ---- Generate TypeScript with JSON data ----
json_str = json.dumps(data, ensure_ascii=False, separators=(',', ':'))

ts_content = f"""// Auto-generated compact region data
export interface RegionNode {{ name: string; children?: (string | RegionNode)[] }}
function toOpts(nodes: (string | RegionNode)[]): any[] {{
  return nodes.map(n => {{
    if (typeof n === 'string') return {{ value: n, label: n }};
    const children = n.children ? toOpts(n.children) : undefined;
    return {{ value: n.name, label: n.name, children }};
  }});
}}
const raw: (string | RegionNode)[] = {json_str};
const regionData = toOpts(raw);
export default regionData;
"""

output_path = 'inv-admin-frontend/src/utils/regionData.ts'
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(ts_content)

import os
size = os.path.getsize(output_path)
print(f"Generated {output_path} ({size} bytes)")
