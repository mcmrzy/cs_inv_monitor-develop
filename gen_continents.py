#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Generate continents data for Flutter and TypeScript from countries list."""
import re
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ISO country code to continent mapping
CONTINENT_MAP = {
    # 浜氭床
    'CN': '浜氭床', 'JP': '浜氭床', 'KR': '浜氭床', 'IN': '浜氭床', 'ID': '浜氭床',
    'TH': '浜氭床', 'VN': '浜氭床', 'MY': '浜氭床', 'SG': '浜氭床', 'PH': '浜氭床',
    'MM': '浜氭床', 'KH': '浜氭床', 'LA': '浜氭床', 'BD': '浜氭床', 'NP': '浜氭床',
    'LK': '浜氭床', 'PK': '浜氭床', 'AF': '浜氭床', 'IR': '浜氭床', 'IQ': '浜氭床',
    'SA': '浜氭床', 'AE': '浜氭床', 'QA': '浜氭床', 'KW': '浜氭床', 'BH': '浜氭床',
    'OM': '浜氭床', 'YE': '浜氭床', 'JO': '浜氭床', 'LB': '浜氭床', 'IL': '浜氭床',
    'PS': '浜氭床', 'SY': '浜氭床', 'KZ': '浜氭床', 'UZ': '浜氭床', 'TM': '浜氭床',
    'TJ': '浜氭床', 'KG': '浜氭床', 'MN': '浜氭床', 'BT': '浜氭床', 'MV': '浜氭床',
    'BN': '浜氭床', 'TL': '浜氭床', 'KP': '浜氭床', 'TW': '浜氭床', 'HK': '浜氭床',
    'MO': '浜氭床', 'AM': '浜氭床', 'AZ': '浜氭床', 'GE': '浜氭床', 'CY': '浜氭床',
    'TR': '浜氭床',
    # 娆ф床
    'GB': '娆ф床', 'DE': '娆ф床', 'FR': '娆ф床', 'IT': '娆ф床', 'ES': '娆ф床',
    'NL': '娆ф床', 'CH': '娆ф床', 'SE': '娆ф床', 'NO': '娆ф床', 'DK': '娆ф床',
    'FI': '娆ф床', 'AT': '娆ф床', 'BE': '娆ф床', 'IE': '娆ф床', 'PT': '娆ф床',
    'GR': '娆ф床', 'PL': '娆ф床', 'CZ': '娆ф床', 'RO': '娆ф床', 'HU': '娆ф床',
    'BG': '娆ф床', 'HR': '娆ф床', 'SK': '娆ф床', 'SI': '娆ф床', 'LT': '娆ф床',
    'LV': '娆ф床', 'EE': '娆ф床', 'LU': '娆ф床', 'MT': '娆ф床', 'IS': '娆ф床',
    'UA': '娆ф床', 'BY': '娆ф床', 'MD': '娆ф床', 'RS': '娆ф床', 'BA': '娆ф床',
    'ME': '娆ф床', 'MK': '娆ф床', 'AL': '娆ф床', 'XK': '娆ф床', 'RU': '娆ф床',
    'AD': '娆ф床', 'MC': '娆ф床', 'SM': '娆ф床', 'LI': '娆ф床', 'VA': '娆ф床',
    'GG': '娆ф床', 'JE': '娆ф床', 'IM': '娆ф床', 'FO': '娆ф床', 'AX': '娆ф床',
    'GL': '娆ф床',
    # 闈炴床
    'NG': '闈炴床', 'KE': '闈炴床', 'ZA': '闈炴床', 'EG': '闈炴床', 'GH': '闈炴床',
    'MA': '闈炴床', 'ET': '闈炴床', 'TZ': '闈炴床', 'DZ': '闈炴床', 'SD': '闈炴床',
    'TN': '闈炴床', 'LY': '闈炴床', 'CM': '闈炴床', 'CI': '闈炴床', 'SN': '闈炴床',
    'UG': '闈炴床', 'MZ': '闈炴床', 'MG': '闈炴床', 'AO': '闈炴床', 'ML': '闈炴床',
    'BF': '闈炴床', 'NE': '闈炴床', 'MW': '闈炴床', 'ZM': '闈炴床', 'ZW': '闈炴床',
    'RW': '闈炴床', 'BW': '闈炴床', 'NA': '闈炴床', 'LS': '闈炴床', 'SZ': '闈炴床',
    'MU': '闈炴床', 'MR': '闈炴床', 'TD': '闈炴床', 'CF': '闈炴床', 'SO': '闈炴床',
    'SS': '闈炴床', 'LY': '闈炴床', 'GN': '闈炴床', 'GW': '闈炴床', 'SL': '闈炴床',
    'LR': '闈炴床', 'TG': '闈炴床', 'BJ': '闈炴床', 'GA': '闈炴床', 'CG': '闈炴床',
    'CD': '闈炴床', 'GQ': '闈炴床', 'BI': '闈炴床', 'DJ': '闈炴床', 'ER': '闈炴床',
    'CV': '闈炴床', 'ST': '闈炴床', 'SC': '闈炴床', 'GM': '闈炴床', 'YT': '闈炴床',
    'RE': '闈炴床', 'SH': '闈炴床',
    # 鍖楃編娲?    'US': '鍖楃編娲?, 'CA': '鍖楃編娲?, 'MX': '鍖楃編娲?, 'GT': '鍖楃編娲?,
    'HN': '鍖楃編娲?, 'SV': '鍖楃編娲?, 'NI': '鍖楃編娲?, 'CR': '鍖楃編娲?,
    'PA': '鍖楃編娲?, 'CU': '鍖楃編娲?, 'JM': '鍖楃編娲?, 'HT': '鍖楃編娲?,
    'DO': '鍖楃編娲?, 'TT': '鍖楃編娲?, 'BZ': '鍖楃編娲?, 'BS': '鍖楃編娲?,
    'AG': '鍖楃編娲?, 'BB': '鍖楃編娲?, 'DM': '鍖楃編娲?, 'GD': '鍖楃編娲?,
    'KN': '鍖楃編娲?, 'LC': '鍖楃編娲?, 'VC': '鍖楃編娲?, 'PR': '鍖楃編娲?,
    'VI': '鍖楃編娲?, 'GP': '鍖楃編娲?, 'MQ': '鍖楃編娲?, 'BM': '鍖楃編娲?,
    'KY': '鍖楃編娲?, 'TC': '鍖楃編娲?, 'MS': '鍖楃編娲?, 'AI': '鍖楃編娲?,
    'MF': '鍖楃編娲?, 'BL': '鍖楃編娲?, 'PM': '鍖楃編娲?, 'AS': '鍖楃編娲?,
    'GU': '鍖楃編娲?, 'MP': '鍖楃編娲?,
    # 鍗楃編娲?    'BR': '鍗楃編娲?, 'AR': '鍗楃編娲?, 'CL': '鍗楃編娲?, 'CO': '鍗楃編娲?,
    'PE': '鍗楃編娲?, 'VE': '鍗楃編娲?, 'EC': '鍗楃編娲?, 'BO': '鍗楃編娲?,
    'PY': '鍗楃編娲?, 'UY': '鍗楃編娲?, 'GY': '鍗楃編娲?, 'SR': '鍗楃編娲?,
    'GF': '鍗楃編娲?, 'FK': '鍗楃編娲?,
    # 澶ф磱娲?    'AU': '澶ф磱娲?, 'NZ': '澶ф磱娲?, 'FJ': '澶ф磱娲?, 'PG': '澶ф磱娲?,
    'WS': '澶ф磱娲?, 'TO': '澶ф磱娲?, 'VU': '澶ф磱娲?, 'SB': '澶ф磱娲?,
    'KI': '澶ф磱娲?, 'MH': '澶ф磱娲?, 'FM': '澶ф磱娲?, 'PW': '澶ф磱娲?,
    'NR': '澶ф磱娲?, 'TV': '澶ф磱娲?, 'NC': '澶ф磱娲?, 'PF': '澶ф磱娲?,
}

# Read countries from china_regions.dart
with open('inv_app/lib/core/data/china_regions.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Parse countries
countries = []
for m in re.finditer(r"{'code': '([^']+)', 'name': '([^']+)'},?\s*//\s*(.+)", content):
    code, name_cn, name_en = m.groups()
    countries.append((code, name_cn, name_en.strip()))

print(f"Total countries parsed: {len(countries)}")

# Group by continent
continent_groups = {}
for code, name_cn, name_en in countries:
    continent = CONTINENT_MAP.get(code, '鍏朵粬')
    continent_groups.setdefault(continent, []).append((code, name_cn, name_en))

# Print summary
for continent in ['浜氭床', '娆ф床', '闈炴床', '鍖楃編娲?, '鍗楃編娲?, '澶ф磱娲?, '鍏朵粬']:
    items = continent_groups.get(continent, [])
    print(f"  {continent}: {len(items)} countries")

# Generate Dart file
dart_lines = []
dart_lines.append('/// 娲蹭笌鍥藉鏄犲皠鏁版嵁')
dart_lines.append('/// 鐢ㄤ簬鍦板尯閫夋嫨鍣ㄧ殑绗竴妗嗭紙娲?鍥藉閫夋嫨锛?)
dart_lines.append('const continents = [')
for continent_name in ['浜氭床', '娆ф床', '闈炴床', '鍖楃編娲?, '鍗楃編娲?, '澶ф磱娲?]:
    items = continent_groups.get(continent_name, [])
    dart_lines.append(f"  {{")
    dart_lines.append(f"    'name': '{continent_name}',")
    dart_lines.append(f"    'countries': [")
    for code, name_cn, name_en in items:
        safe_cn = name_cn.replace("'", "\\'")
        dart_lines.append(f"      {{'code': '{code}', 'name': '{safe_cn}'}},")
    dart_lines.append(f"    ],")
    dart_lines.append(f"  }},")
dart_lines.append('];')

with open('inv_app/lib/core/data/continents_data.dart', 'w', encoding='utf-8') as f:
    f.write('\n'.join(dart_lines))

print("Generated continents_data.dart")

# Generate TypeScript file
ts_lines = []
ts_lines.append('// 娲蹭笌鍥藉鏄犲皠鏁版嵁')
ts_lines.append('// 鐢ㄤ簬鍦板尯閫夋嫨鍣ㄧ殑绗竴妗嗭紙娲?鍥藉閫夋嫨锛?)
ts_lines.append('')
ts_lines.append('export interface ContinentOption {')
ts_lines.append('  name: string')
ts_lines.append('  countries: { code: string; name: string }[]')
ts_lines.append('}')
ts_lines.append('')
ts_lines.append('const continentsData: ContinentOption[] = [')
for continent_name in ['浜氭床', '娆ф床', '闈炴床', '鍖楃編娲?, '鍗楃編娲?, '澶ф磱娲?]:
    items = continent_groups.get(continent_name, [])
    ts_lines.append(f"  {{")
    ts_lines.append(f"    name: '{continent_name}',")
    ts_lines.append(f"    countries: [")
    for code, name_cn, name_en in items:
        safe_cn = name_cn.replace("'", "\\'")
        ts_lines.append(f"      {{ code: '{code}', name: '{safe_cn}' }},")
    ts_lines.append(f"    ],")
    ts_lines.append(f"  }},")
ts_lines.append(']')
ts_lines.append('')
ts_lines.append('export default continentsData')

with open('inv-admin-frontend/src/utils/continentsData.ts', 'w', encoding='utf-8') as f:
    f.write('\n'.join(ts_lines))

print("Generated continentsData.ts")
