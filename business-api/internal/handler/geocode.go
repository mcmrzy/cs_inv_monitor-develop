package handler

import (
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"sync"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var geocodeHTTPClient = &http.Client{Timeout: 10 * time.Second}

// flexString 兼容高德 API 中 address 字段可能返回 [] (空数组) 而非字符串的情况
type flexString string

func (f *flexString) UnmarshalJSON(data []byte) error {
	if len(data) > 0 && data[0] == '[' {
		*f = ""
		return nil
	}
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}
	*f = flexString(s)
	return nil
}

// regionCache 缓存服务器出口 IP 所属区域，避免重复调用 ip-api.com
var (
	regionCache     string
	regionCacheOnce bool
	regionCacheMu   sync.Mutex
)

// GeocodeHandler 提供地理编码 API 供前端调用
type GeocodeHandler struct {
	stationService *service.StationService
	amapAPIKey     string
}

func NewGeocodeHandler(stationService *service.StationService, amapAPIKey string) *GeocodeHandler {
	return &GeocodeHandler{
		stationService: stationService,
		amapAPIKey:     amapAPIKey,
	}
}

// Geocode 正向地理编码：地址 → 坐标
// GET /api/v1/geocode?address=xxx&country=xxx
func (h *GeocodeHandler) Geocode(c *gin.Context) {
	address := c.Query("address")
	country := c.Query("country")
	if address == "" {
		response.Error(c, 400, "address is required")
		return
	}

	lat, lng, err := geocodeByText(address, country, h.amapAPIKey)
	if err != nil {
		logger.Warn("Geocode API failed", zap.String("address", address), zap.Error(err))
		response.Error(c, 502, "geocode failed: "+err.Error())
		return
	}

	response.Success(c, gin.H{
		"lat": lat,
		"lng": lng,
	})
}

// ReverseGeocode 逆向地理编码：坐标 → 地址 + 附近 POI 列表
// GET /api/v1/geocode/reverse?lat=28.21&lng=112.88
func (h *GeocodeHandler) ReverseGeocode(c *gin.Context) {
	latStr := c.Query("lat")
	lngStr := c.Query("lng")
	lat, err1 := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err1 != nil || err2 != nil {
		response.Error(c, 400, "invalid lat or lng")
		return
	}

	// 中国坐标：优先用高德 regeo（一次请求同时获取地址 + 附近 POI）
	if coordInChina(lat, lng) && h.amapAPIKey != "" {
		result, err := reverseGeocodeAmap(lat, lng, h.amapAPIKey)
		if err == nil {
			response.Success(c, result)
			return
		}
		logger.Warn("Amap regeo failed, falling back to Nominatim",
			zap.Float64("lat", lat), zap.Float64("lng", lng), zap.Error(err))
	}

	// 海外或高德失败：fallback 到 Nominatim
	result, err := reverseGeocodeNominatim(lat, lng)
	if err != nil {
		logger.Warn("Reverse geocode failed", zap.Float64("lat", lat), zap.Float64("lng", lng), zap.Error(err))
		response.Error(c, 502, "reverse geocode failed: "+err.Error())
		return
	}

	response.Success(c, result)
}

// DetectRegion 检测服务器出口 IP 所属区域，供前端决定地图瓦片源
// GET /api/v1/geo/detect-region
// 返回 {"region": "CN"} 或 {"region": "global"}
func (h *GeocodeHandler) DetectRegion(c *gin.Context) {
	regionCacheMu.Lock()
	defer regionCacheMu.Unlock()

	if regionCacheOnce {
		response.Success(c, gin.H{"region": regionCache})
		return
	}

	region := detectServerRegion()
	regionCache = region
	regionCacheOnce = true
	logger.Info("Server region detected", zap.String("region", region))
	response.Success(c, gin.H{"region": region})
}

// detectServerRegion 通过 ip-api.com 检测服务器出口 IP 所属国家
func detectServerRegion() string {
	type ipAPIResult struct {
	Status      string `json:"status"`
	CountryCode string `json:"countryCode"`
	}

	resp, err := geocodeHTTPClient.Get("http://ip-api.com/json/?fields=status,countryCode")
	if err != nil {
		logger.Warn("ip-api.com request failed, defaulting to CN", zap.Error(err))
		return "CN"
	}
	defer resp.Body.Close()

	var result ipAPIResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		logger.Warn("ip-api.com parse failed, defaulting to CN", zap.Error(err))
		return "CN"
	}

	if result.Status != "success" || result.CountryCode == "" {
		logger.Warn("ip-api.com returned no result, defaulting to CN")
		return "CN"
	}

	return result.CountryCode
}

// ============================================================
// 内部地理编码函数
// ============================================================

// geocodeByAddress 根据省市区+国家进行地理编码（供 station_handler 内部调用）
func geocodeByAddress(province, city, district, country, amapKey string) (float64, float64, error) {
	if isChina(country) {
		// 中国优先用高德
		lat, lng, err := geocodeAddressAmap(province, city, district, amapKey)
		if err == nil {
			return lat, lng, nil
		}
		logger.Warn("Amap geocode failed, falling back to Nominatim",
			zap.String("province", province), zap.Error(err))
	}
	// 海外或高德失败时，fallback 到 Nominatim
	parts := filterEmpty([]string{district, city, province, country})
	fullAddr := strings.Join(parts, ", ")
	return geocodeAddressNominatim(fullAddr)
}

// geocodeByText 根据文本地址进行地理编码（供 API 和内部共用）
func geocodeByText(address, country, amapKey string) (float64, float64, error) {
	if isChina(country) {
		// 中国优先用高德，将 address 拆给高德
		lat, lng, err := geocodeAddressAmap(address, "", "", amapKey)
		if err == nil {
			return lat, lng, nil
		}
	}
	return geocodeAddressNominatim(address)
}

// reverseGeocode 逆向地理编码：坐标 → 地址信息（内部调用，供 station_handler 使用）
func reverseGeocode(lat, lng float64) (*ReverseGeocodeResult, error) {
	return reverseGeocodeNominatim(lat, lng)
}

// ReverseGeocodeResult 逆向地理编码结果
type ReverseGeocodeResult struct {
	Province string            `json:"province"`
	City     string            `json:"city"`
	District string            `json:"district"`
	Address  string            `json:"address"`
	Country  string            `json:"country"`
	Road     string            `json:"road"`
	Hamlet   string            `json:"hamlet"`
	Nearby   []NearbyAddress   `json:"nearby"`
}

// NearbyAddress 附近地址条目（类似外卖 App 的地址列表）
type NearbyAddress struct {
	Name   string  `json:"name"`   // 地点名称（如 "麓谷企业广场"）
	Detail string  `json:"detail"` // 详细地址（如 "文轩路123号"）
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
}

// ============================================================
// 高德地理编码（中国）
// ============================================================

func geocodeAddressAmap(province, city, district, amapKey string) (float64, float64, error) {
	if amapKey == "" {
		return 0, 0, fmt.Errorf("amap api key not configured")
	}

	address := province + city + district
	if address == "" {
		return 0, 0, fmt.Errorf("empty address")
	}
	resp, err := geocodeHTTPClient.Get(fmt.Sprintf(
		"https://restapi.amap.com/v3/geocode/geo?address=%s&key=%s",
		url.QueryEscape(address), amapKey,
	))
	if err != nil {
		logger.Warn("Amap geocode request failed", zap.String("address", address), zap.Error(err))
		return 0, 0, err
	}
	defer resp.Body.Close()

	var result struct {
		Status   string `json:"status"`
		Geocodes []struct {
			Location string `json:"location"`
		} `json:"geocodes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		logger.Warn("Failed to parse Amap response", zap.Error(err))
		return 0, 0, err
	}
	if result.Status != "1" || len(result.Geocodes) == 0 {
		logger.Warn("Amap returned no result", zap.String("address", address), zap.String("status", result.Status))
		return 0, 0, fmt.Errorf("amap geocode failed or no result for: %s", address)
	}

	parts := strings.Split(result.Geocodes[0].Location, ",")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid location format: %s", result.Geocodes[0].Location)
	}
	lng, _ := strconv.ParseFloat(parts[0], 64)
	lat, _ := strconv.ParseFloat(parts[1], 64)

	// 高德返回的是 GCJ-02 坐标，转为 WGS-84 存储
	wgsLat, wgsLng := gcj02ToWgs84(lat, lng)
	logger.Info("Amap geocode success", zap.String("address", address), zap.Float64("wgs84_lat", wgsLat), zap.Float64("wgs84_lng", wgsLng))
	return wgsLat, wgsLng, nil
}

// ============================================================
// Nominatim 地理编码（全球，OpenStreetMap）
// ============================================================

func geocodeAddressNominatim(address string) (float64, float64, error) {
	if address == "" {
		return 0, 0, fmt.Errorf("empty address")
	}

	req, err := http.NewRequest("GET",
		fmt.Sprintf("https://nominatim.openstreetmap.org/search?q=%s&format=json&limit=1",
			url.QueryEscape(address)),
		nil,
	)
	if err != nil {
		return 0, 0, err
	}
	req.Header.Set("User-Agent", "cs-inv-monitor/1.0")
	req.Header.Set("Accept-Language", "zh,en")

	resp, err := geocodeHTTPClient.Do(req)
	if err != nil {
		logger.Warn("Nominatim request failed", zap.String("address", address), zap.Error(err))
		return 0, 0, err
	}
	defer resp.Body.Close()

	var results []struct {
		Lat string `json:"lat"`
		Lon string `json:"lon"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
		logger.Warn("Failed to parse Nominatim response", zap.Error(err))
		return 0, 0, err
	}
	if len(results) == 0 {
		return 0, 0, fmt.Errorf("nominatim: no result for: %s", address)
	}

	lat, _ := strconv.ParseFloat(results[0].Lat, 64)
	lng, _ := strconv.ParseFloat(results[0].Lon, 64)

	logger.Info("Nominatim geocode success", zap.String("address", address), zap.Float64("lat", lat), zap.Float64("lng", lng))
	return lat, lng, nil
}

func reverseGeocodeNominatim(lat, lng float64) (*ReverseGeocodeResult, error) {
	req, err := http.NewRequest("GET",
		fmt.Sprintf("https://nominatim.openstreetmap.org/reverse?lat=%.6f&lon=%.6f&format=json&accept-language=zh",
			lat, lng),
		nil,
	)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "cs-inv-monitor/1.0")

	resp, err := geocodeHTTPClient.Do(req)
	if err != nil {
		logger.Warn("Nominatim reverse request failed", zap.Float64("lat", lat), zap.Float64("lng", lng), zap.Error(err))
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		DisplayName string `json:"display_name"`
		Address     struct {
			Country      string `json:"country"`
			State        string `json:"state"`
			Province     string `json:"province"`
			City         string `json:"city"`
			Town         string `json:"town"`
			County       string `json:"county"`
			Suburb       string `json:"suburb"`
			CityDistrict string `json:"city_district"`
			Village      string `json:"village"`
			Hamlet       string `json:"hamlet"`
			Road         string `json:"road"`
			HouseNumber  string `json:"house_number"`
			Neighbourhood string `json:"neighbourhood"`
		} `json:"address"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		logger.Warn("Failed to parse Nominatim reverse response", zap.Error(err))
		return nil, err
	}

	province := result.Address.State
	if province == "" {
		province = result.Address.Province
	}
	city := result.Address.City
	if city == "" {
		city = result.Address.Town
	}
	if city == "" {
		city = result.Address.County
	}
	district := result.Address.Suburb
	if district == "" {
		district = result.Address.CityDistrict
	}
	if district == "" {
		district = result.Address.Village
	}

	// 构造简洁地址：路名 + 门牌号（类似外卖定位格式）
	road := result.Address.Road
	shortAddr := road
	if result.Address.HouseNumber != "" {
		shortAddr = road + result.Address.HouseNumber + "号"
	}
	if shortAddr == "" {
		// 没有路名时，用 neighbourhood/hamlet
		shortAddr = result.Address.Neighbourhood
		if shortAddr == "" {
			shortAddr = result.Address.Hamlet
		}
	}
	if shortAddr == "" {
		shortAddr = result.DisplayName // 最终 fallback
	}

	return &ReverseGeocodeResult{
		Province: province,
		City:     city,
		District: district,
		Address:  shortAddr,
		Country:  result.Address.Country,
		Road:     road,
		Hamlet:   result.Address.Hamlet,
	}, nil
}

// ============================================================
// 高德逆向地理编码 + 附近 POI（中国区域，一次请求）
// ============================================================

// reverseGeocodeAmap 调用高德 regeo API（extensions=all）
// 一次请求同时返回结构化地址 + 附近 POI 列表
func reverseGeocodeAmap(lat, lng float64, amapKey string) (*ReverseGeocodeResult, error) {
	// WGS-84 → GCJ-02 坐标转换（高德使用 GCJ-02 坐标系）
	gcjLat, gcjLng := wgs84ToGcj02(lat, lng)

	regeoURL := fmt.Sprintf(
		"https://restapi.amap.com/v3/geocode/regeo?location=%.6f,%.6f&key=%s&extensions=all&radius=500&output=json",
		gcjLng, gcjLat, amapKey,
	)

	resp, err := geocodeHTTPClient.Get(regeoURL)
	if err != nil {
		return nil, fmt.Errorf("amap regeo request failed: %w", err)
	}
	defer resp.Body.Close()

	var result struct {
		Status    string `json:"status"`
		Info      string `json:"info"`
		Regeocode struct {
			FormattedAddress string `json:"formatted_address"`
			AddressComponent struct {
				Province  flexString `json:"province"`
				City      flexString `json:"city"`
				District  flexString `json:"district"`
				Township  flexString `json:"township"`
				Country   string `json:"country"`
				StreetNumber struct {
					Street string `json:"street"`
					Number string `json:"number"`
				} `json:"streetNumber"`
			} `json:"addressComponent"`
			Pois []struct {
				Name     string     `json:"name"`
				Address  flexString `json:"address"`
				Location string     `json:"location"` // "lng,lat"
				Distance string     `json:"distance"`
			} `json:"pois"`
		} `json:"regeocode"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("amap regeo parse failed: %w", err)
	}
	if result.Status != "1" {
		return nil, fmt.Errorf("amap regeo failed: %s", result.Info)
	}

	comp := result.Regeocode.AddressComponent

	// 构造简洁地址：优先用街道+门牌号，否则用 formatted_address 的后半段
	shortAddr := comp.StreetNumber.Street
	if comp.StreetNumber.Number != "" {
		shortAddr += comp.StreetNumber.Number + "号"
	}
	if shortAddr == "" {
		// fallback: 从 formatted_address 提取（去掉省市区前缀）
		shortAddr = result.Regeocode.FormattedAddress
		// 尝试去掉省市区前缀，只保留街道以下
		for _, prefix := range []string{string(comp.Province), string(comp.City), string(comp.District), string(comp.Township)} {
			if prefix != "" && strings.HasPrefix(shortAddr, prefix) {
				shortAddr = strings.TrimPrefix(shortAddr, prefix)
			}
		}
		shortAddr = strings.TrimSpace(shortAddr)
	}
	if shortAddr == "" {
		shortAddr = result.Regeocode.FormattedAddress
	}

	// 解析附近 POI 列表
	var nearby []NearbyAddress
	for _, poi := range result.Regeocode.Pois {
		if poi.Name == "" {
			continue
		}
		var pLat, pLng float64
		if parts := strings.Split(poi.Location, ","); len(parts) == 2 {
			pLng, _ = strconv.ParseFloat(parts[0], 64)
			pLat, _ = strconv.ParseFloat(parts[1], 64)
			// 高德 POI 坐标为 GCJ-02，转为 WGS-84 统一存储
			pLat, pLng = gcj02ToWgs84(pLat, pLng)
		}
		detail := string(poi.Address)
		if detail == "" {
			detail = string(comp.Township)
		}
		nearby = append(nearby, NearbyAddress{
			Name:   poi.Name,
			Detail: detail,
			Lat:    pLat,
			Lng:    pLng,
		})
	}

	city := string(comp.City)
	if city == "" {
		city = string(comp.Province) // 直辖市时 city 为空
	}

	return &ReverseGeocodeResult{
		Province: string(comp.Province),
		City:     city,
		District: string(comp.District),
		Address:  shortAddr,
		Country:  "中国",
		Road:     comp.StreetNumber.Street,
		Hamlet:   string(comp.Township),
		Nearby:   nearby,
	}, nil
}

// coordInChina 判断坐标是否在中国境内（粗略边界框）
func coordInChina(lat, lng float64) bool {
	return lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271
}

// ============================================================
// WGS-84 → GCJ-02 坐标转换（中国地图偏移纠正）
// ============================================================

const (
	gcjA  = 6378245.0
	gcjEE = 0.00669342162296594323
)

func wgs84ToGcj02(lat, lng float64) (float64, float64) {
	if !coordInChina(lat, lng) {
		return lat, lng
	}
	dLat := transformLat(lng-105.0, lat-35.0)
	dLng := transformLng(lng-105.0, lat-35.0)
	radLat := lat / 180.0 * math.Pi
	magic := math.Sin(radLat)
	magic = 1 - gcjEE*magic*magic
	sqrtMagic := math.Sqrt(magic)
	dLat = (dLat * 180.0) / ((gcjA * (1 - gcjEE)) / (magic * sqrtMagic) * math.Pi)
	dLng = (dLng * 180.0) / (gcjA / sqrtMagic * math.Cos(radLat) * math.Pi)
	return lat + dLat, lng + dLng
}

// gcj02ToWgs84 将高德 API 返回的 GCJ-02 坐标转换为 WGS-84（迭代逼近法，精度 < 0.5mm）
func gcj02ToWgs84(lat, lng float64) (float64, float64) {
	if !coordInChina(lat, lng) {
		return lat, lng
	}
	wgsLat, wgsLng := lat, lng
	for i := 0; i < 5; i++ {
		gcjLat, gcjLng := wgs84ToGcj02(wgsLat, wgsLng)
		dLat := gcjLat - lat
		dLng := gcjLng - lng
		wgsLat -= dLat
		wgsLng -= dLng
		if math.Abs(dLat) < 1e-9 && math.Abs(dLng) < 1e-9 {
			break
		}
	}
	return wgsLat, wgsLng
}

func transformLat(x, y float64) float64 {
	ret := -100.0 + 2.0*x + 3.0*y + 0.2*y*y + 0.1*x*y + 0.2*math.Sqrt(math.Abs(x))
	ret += (20.0*math.Sin(6.0*x*math.Pi) + 20.0*math.Sin(2.0*x*math.Pi)) * 2.0 / 3.0
	ret += (20.0*math.Sin(y*math.Pi) + 40.0*math.Sin(y/3.0*math.Pi)) * 2.0 / 3.0
	ret += (160.0*math.Sin(y/12.0*math.Pi) + 320.0*math.Sin(y*math.Pi/30.0)) * 2.0 / 3.0
	return ret
}

func transformLng(x, y float64) float64 {
	ret := 300.0 + x + 2.0*y + 0.1*x*x + 0.1*x*y + 0.1*math.Sqrt(math.Abs(x))
	ret += (20.0*math.Sin(6.0*x*math.Pi) + 20.0*math.Sin(2.0*x*math.Pi)) * 2.0 / 3.0
	ret += (20.0*math.Sin(x*math.Pi) + 40.0*math.Sin(x/3.0*math.Pi)) * 2.0 / 3.0
	ret += (150.0*math.Sin(x/12.0*math.Pi) + 300.0*math.Sin(x/30.0*math.Pi)) * 2.0 / 3.0
	return ret
}

// ============================================================
// 辅助函数
// ============================================================

func isChina(country string) bool {
	return country == "" || country == "中国" || country == "China" || country == "CN"
}

func filterEmpty(parts []string) []string {
	var result []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			result = append(result, p)
		}
	}
	return result
}
