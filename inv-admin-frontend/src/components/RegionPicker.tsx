import React, { useState, useRef, useEffect } from 'react';
import { Modal, Input } from 'antd';
import { EnvironmentOutlined } from '@ant-design/icons';

interface RegionOption {
  value: string;
  label: string;
  children?: RegionOption[];
}

interface RegionPickerProps {
  value?: string[];
  onChange?: (value: string[]) => void;
  options: RegionOption[];
  placeholder?: string;
  style?: React.CSSProperties;
}

const RegionPicker: React.FC<RegionPickerProps> = ({
  value = [],
  onChange,
  options,
  placeholder = '请选择国家/地区',
  style,
}) => {
  const [visible, setVisible] = useState(false);
  const [selectedCountry, setSelectedCountry] = useState<string>(value[0] || '');
  const [selectedRegion, setSelectedRegion] = useState<string>(value[1] || '');
  const [selectedCity, setSelectedCity] = useState<string>(value[2] || '');
  const [countryScrollTop, setCountryScrollTop] = useState(0);
  const [regionScrollTop, setRegionScrollTop] = useState(0);
  const [cityScrollTop, setCityScrollTop] = useState(0);

  const countryRef = useRef<HTMLDivElement>(null);
  const regionRef = useRef<HTMLDivElement>(null);
  const cityRef = useRef<HTMLDivElement>(null);

  // 获取选中的标签
  const getDisplayText = () => {
    if (value.length === 0) return placeholder;
    
    const country = options.find(c => c.value === value[0]);
    if (!country) return placeholder;
    
    let text = country.label;
    if (value.length > 1 && country.children) {
      const region = country.children.find(r => r.value === value[1]);
      if (region) {
        text += ' / ' + region.label;
        if (value.length > 2 && region.children) {
          const city = region.children.find(c => c.value === value[2]);
          if (city) {
            text += ' / ' + city.label;
          }
        }
      }
    }
    return text;
  };

  // 滚动到选中项
  const scrollToSelected = (ref: React.RefObject<HTMLDivElement>, index: number) => {
    if (ref.current) {
      const itemHeight = 44;
      const containerHeight = ref.current.clientHeight;
      const scrollPosition = index * itemHeight - containerHeight / 2 + itemHeight / 2;
      ref.current.scrollTop = Math.max(0, scrollPosition);
    }
  };

  // 打开弹窗时滚动到选中项
  useEffect(() => {
    if (visible) {
      const countryIndex = options.findIndex(c => c.value === selectedCountry);
      if (countryIndex >= 0) {
        setTimeout(() => scrollToSelected(countryRef, countryIndex), 100);
      }

      if (selectedCountry) {
        const country = options.find(c => c.value === selectedCountry);
        if (country?.children) {
          const regionIndex = country.children.findIndex(r => r.value === selectedRegion);
          if (regionIndex >= 0) {
            setTimeout(() => scrollToSelected(regionRef, regionIndex), 100);
          }
        }
      }
    }
  }, [visible, selectedCountry, selectedRegion, options]);

  const handleCountrySelect = (country: RegionOption) => {
    setSelectedCountry(country.value);
    setSelectedRegion('');
    setSelectedCity('');
  };

  const handleRegionSelect = (region: RegionOption) => {
    setSelectedRegion(region.value);
    setSelectedCity('');
  };

  const handleCitySelect = (city: RegionOption) => {
    setSelectedCity(city.value);
  };

  const handleConfirm = () => {
    const result = [selectedCountry, selectedRegion, selectedCity].filter(Boolean);
    onChange?.(result);
    setVisible(false);
  };

  const handleCancel = () => {
    // 恢复原值
    setSelectedCountry(value[0] || '');
    setSelectedRegion(value[1] || '');
    setSelectedCity(value[2] || '');
    setVisible(false);
  };

  // 获取当前国家的地区列表
  const currentRegions = options.find(c => c.value === selectedCountry)?.children || [];
  
  // 获取当前地区的城市列表
  const currentCities = currentRegions.find(r => r.value === selectedRegion)?.children || [];

  return (
    <>
      <Input
        value={getDisplayText()}
        placeholder={placeholder}
        readOnly
        prefix={<EnvironmentOutlined />}
        onClick={() => setVisible(true)}
        style={{ cursor: 'pointer', ...style }}
      />
      
      <Modal
        title="选择国家/地区"
        open={visible}
        onOk={handleConfirm}
        onCancel={handleCancel}
        width={480}
        okText="确认"
        cancelText="取消"
      >
        <div style={styles.container}>
          {/* 国家滚轮 */}
          <div style={styles.column}>
            <div style={styles.columnHeader}>国家</div>
            <div
              ref={countryRef}
              style={styles.scrollContainer}
            >
              {options.map((country) => (
                <div
                  key={country.value}
                  style={{
                    ...styles.item,
                    ...(selectedCountry === country.value ? styles.selectedItem : {}),
                  }}
                  onClick={() => handleCountrySelect(country)}
                >
                  {country.label}
                </div>
              ))}
            </div>
          </div>

          {/* 地区滚轮 */}
          {currentRegions.length > 0 && (
            <div style={styles.column}>
              <div style={styles.columnHeader}>省份/地区</div>
              <div
                ref={regionRef}
                style={styles.scrollContainer}
              >
                {currentRegions.map((region) => (
                  <div
                    key={region.value}
                    style={{
                      ...styles.item,
                      ...(selectedRegion === region.value ? styles.selectedItem : {}),
                    }}
                    onClick={() => handleRegionSelect(region)}
                  >
                    {region.label}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 城市滚轮 */}
          {currentCities.length > 0 && (
            <div style={styles.column}>
              <div style={styles.columnHeader}>城市</div>
              <div
                ref={cityRef}
                style={styles.scrollContainer}
              >
                {currentCities.map((city) => (
                  <div
                    key={city.value}
                    style={{
                      ...styles.item,
                      ...(selectedCity === city.value ? styles.selectedItem : {}),
                    }}
                    onClick={() => handleCitySelect(city)}
                  >
                    {city.label}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </Modal>
    </>
  );
};

const styles: Record<string, React.CSSProperties> = {
  container: {
    display: 'flex',
    height: 400,
    border: '1px solid #f0f0f0',
    borderRadius: 8,
    overflow: 'hidden',
  },
  column: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    borderRight: '1px solid #f0f0f0',
  },
  columnHeader: {
    padding: '12px 16px',
    backgroundColor: '#fafafa',
    borderBottom: '1px solid #f0f0f0',
    fontWeight: 600,
    fontSize: 14,
    color: '#333',
    textAlign: 'center',
  },
  scrollContainer: {
    flex: 1,
    overflowY: 'auto',
    scrollbarWidth: 'thin',
  },
  item: {
    padding: '12px 16px',
    cursor: 'pointer',
    transition: 'all 0.2s',
    fontSize: 14,
    color: '#666',
    borderBottom: '1px solid #fafafa',
    textAlign: 'center',
  },
  selectedItem: {
    color: '#1677ff',
    fontWeight: 600,
    backgroundColor: '#e6f4ff',
  },
};

export default RegionPicker;
