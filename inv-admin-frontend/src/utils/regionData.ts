// 国家/地区/省市数据 - 主要覆盖中国、美国、澳大利亚、欧洲等
export interface RegionOption {
  value: string
  label: string
  children?: RegionOption[]
}

const regionData: RegionOption[] = [
  {
    value: 'CN',
    label: '中国',
    children: [
      {
        value: 'guangdong',
        label: '广东省',
        children: [
          { value: 'shenzhen', label: '深圳市' },
          { value: 'guangzhou', label: '广州市' },
          { value: 'dongguan', label: '东莞市' },
          { value: 'foshan', label: '佛山市' },
          { value: 'zhuhai', label: '珠海市' },
          { value: 'zhongshan', label: '中山市' },
          { value: 'huizhou', label: '惠州市' },
        ],
      },
      {
        value: 'zhejiang',
        label: '浙江省',
        children: [
          { value: 'hangzhou', label: '杭州市' },
          { value: 'ningbo', label: '宁波市' },
          { value: 'wenzhou', label: '温州市' },
          { value: 'jiaxing', label: '嘉兴市' },
          { value: 'shaoxing', label: '绍兴市' },
        ],
      },
      {
        value: 'jiangsu',
        label: '江苏省',
        children: [
          { value: 'nanjing', label: '南京市' },
          { value: 'suzhou', label: '苏州市' },
          { value: 'wuxi', label: '无锡市' },
          { value: 'changzhou', label: '常州市' },
          { value: 'nantong', label: '南通市' },
        ],
      },
      {
        value: 'shanghai',
        label: '上海市',
        children: [
          { value: 'pudong', label: '浦东新区' },
          { value: 'huangpu', label: '黄浦区' },
          { value: 'jing_an', label: '静安区' },
          { value: 'xuhui', label: '徐汇区' },
          { value: 'changning', label: '长宁区' },
        ],
      },
      {
        value: 'beijing',
        label: '北京市',
        children: [
          { value: 'chaoyang', label: '朝阳区' },
          { value: 'haidian', label: '海淀区' },
          { value: 'dongcheng', label: '东城区' },
          { value: 'xicheng', label: '西城区' },
          { value: 'fengtai', label: '丰台区' },
        ],
      },
      {
        value: 'sichuan',
        label: '四川省',
        children: [
          { value: 'chengdu', label: '成都市' },
          { value: 'mianyang', label: '绵阳市' },
          { value: 'deyang', label: '德阳市' },
        ],
      },
      {
        value: 'hubei',
        label: '湖北省',
        children: [
          { value: 'wuhan', label: '武汉市' },
          { value: 'yichang', label: '宜昌市' },
          { value: 'xiangyang', label: '襄阳市' },
        ],
      },
      {
        value: 'hunan',
        label: '湖南省',
        children: [
          { value: 'changsha', label: '长沙市' },
          { value: 'zhuzhou', label: '株洲市' },
          { value: 'xiangtan', label: '湘潭市' },
        ],
      },
      {
        value: 'fujian',
        label: '福建省',
        children: [
          { value: 'fuzhou', label: '福州市' },
          { value: 'xiamen', label: '厦门市' },
          { value: 'quanzhou', label: '泉州市' },
        ],
      },
      {
        value: 'shandong',
        label: '山东省',
        children: [
          { value: 'jinan', label: '济南市' },
          { value: 'qingdao', label: '青岛市' },
          { value: 'yantai', label: '烟台市' },
        ],
      },
    ],
  },
  {
    value: 'US',
    label: 'United States',
    children: [
      {
        value: 'california',
        label: 'California',
        children: [
          { value: 'los_angeles', label: 'Los Angeles' },
          { value: 'san_francisco', label: 'San Francisco' },
          { value: 'san_diego', label: 'San Diego' },
          { value: 'san_jose', label: 'San Jose' },
        ],
      },
      {
        value: 'new_york',
        label: 'New York',
        children: [
          { value: 'new_york_city', label: 'New York City' },
          { value: 'buffalo', label: 'Buffalo' },
          { value: 'albany', label: 'Albany' },
        ],
      },
      {
        value: 'texas',
        label: 'Texas',
        children: [
          { value: 'houston', label: 'Houston' },
          { value: 'dallas', label: 'Dallas' },
          { value: 'austin', label: 'Austin' },
          { value: 'san_antonio', label: 'San Antonio' },
        ],
      },
      {
        value: 'florida',
        label: 'Florida',
        children: [
          { value: 'miami', label: 'Miami' },
          { value: 'orlando', label: 'Orlando' },
          { value: 'tampa', label: 'Tampa' },
        ],
      },
    ],
  },
  {
    value: 'AU',
    label: 'Australia',
    children: [
      {
        value: 'new_south_wales',
        label: 'New South Wales',
        children: [
          { value: 'sydney', label: 'Sydney' },
          { value: 'newcastle', label: 'Newcastle' },
          { value: 'wollongong', label: 'Wollongong' },
        ],
      },
      {
        value: 'victoria',
        label: 'Victoria',
        children: [
          { value: 'melbourne', label: 'Melbourne' },
          { value: 'geelong', label: 'Geelong' },
        ],
      },
      {
        value: 'queensland',
        label: 'Queensland',
        children: [
          { value: 'brisbane', label: 'Brisbane' },
          { value: 'gold_coast', label: 'Gold Coast' },
          { value: 'cairns', label: 'Cairns' },
        ],
      },
      {
        value: 'western_australia',
        label: 'Western Australia',
        children: [
          { value: 'perth', label: 'Perth' },
        ],
      },
    ],
  },
  {
    value: 'DE',
    label: 'Germany',
    children: [
      {
        value: 'bavaria',
        label: 'Bavaria',
        children: [
          { value: 'munich', label: 'Munich' },
          { value: 'nuremberg', label: 'Nuremberg' },
        ],
      },
      {
        value: 'berlin',
        label: 'Berlin',
        children: [
          { value: 'berlin_city', label: 'Berlin' },
        ],
      },
      {
        value: 'north_rhine_westphalia',
        label: 'North Rhine-Westphalia',
        children: [
          { value: 'cologne', label: 'Cologne' },
          { value: 'dusseldorf', label: 'Düsseldorf' },
        ],
      },
    ],
  },
  {
    value: 'GB',
    label: 'United Kingdom',
    children: [
      {
        value: 'england',
        label: 'England',
        children: [
          { value: 'london', label: 'London' },
          { value: 'manchester', label: 'Manchester' },
          { value: 'birmingham', label: 'Birmingham' },
          { value: 'liverpool', label: 'Liverpool' },
        ],
      },
      {
        value: 'scotland',
        label: 'Scotland',
        children: [
          { value: 'edinburgh', label: 'Edinburgh' },
          { value: 'glasgow', label: 'Glasgow' },
        ],
      },
    ],
  },
  {
    value: 'JP',
    label: 'Japan',
    children: [
      {
        value: 'tokyo',
        label: 'Tokyo',
        children: [
          { value: 'shibuya', label: 'Shibuya' },
          { value: 'shinjuku', label: 'Shinjuku' },
        ],
      },
      {
        value: 'osaka',
        label: 'Osaka',
        children: [
          { value: 'osaka_city', label: 'Osaka City' },
        ],
      },
    ],
  },
  {
    value: 'KR',
    label: 'South Korea',
    children: [
      {
        value: 'seoul',
        label: 'Seoul',
        children: [
          { value: 'gangnam', label: 'Gangnam' },
          { value: 'jongno', label: 'Jongno' },
        ],
      },
      {
        value: 'busan',
        label: 'Busan',
        children: [
          { value: 'haeundae', label: 'Haeundae' },
        ],
      },
    ],
  },
  {
    value: 'SG',
    label: 'Singapore',
    children: [
      {
        value: 'central',
        label: 'Central Region',
        children: [
          { value: 'orchard', label: 'Orchard' },
          { value: 'marina_bay', label: 'Marina Bay' },
        ],
      },
    ],
  },
]

export default regionData
