package handler

import (
	"encoding/json"
	"fmt"
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

// ReverseGeocode 逆向地理编码：坐标 → 地址
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

	result, err := reverseGeocode(lat, lng)
	if err != nil {
		logger.Warn("Reverse geocode failed", zap.Float64("lat", lat), zap.Float64("lng", lng), zap.Error(err))
		response.Error(c, 502, "reverse geocode failed: "+err.Error())
		return
	}

	// 搜索附近地址列表（类似外卖 App）
	nearby := searchNearbyAddresses(lat, lng)
	result.Nearby = nearby

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

// reverseGeocode 逆向地理编码：坐标 → 地址信息
func reverseGeocode(lat, lng float64) (*ReverseGeocodeResult, error) {
	// 优先尝试 Nominatim（全球通用）
	result, err := reverseGeocodeNominatim(lat, lng)
	if err == nil {
		return result, nil
	}
	// Nominatim 失败时返回错误
	return nil, fmt.Errorf("reverse geocode failed: %w", err)
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

	logger.Info("Amap geocode success", zap.String("address", address), zap.Float64("lat", lat), zap.Float64("lng", lng))
	return lat, lng, nil
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
// 附近地址搜索（类似外卖 App 的地址列表）
// ============================================================

// searchNearbyAddresses 搜索坐标附近的地址列表
func searchNearbyAddresses(lat, lng float64) []NearbyAddress {
	// 使用 Nominatim search 在坐标附近搜索地址
	// viewbox 限定搜索范围在坐标附近约 500m
	delta := 0.005 // 约 500m
	viewbox := fmt.Sprintf("%f,%f,%f,%f", lng-delta, lat+delta, lng+delta, lat-delta)

	req, err := http.NewRequest("GET",
		fmt.Sprintf("https://nominatim.openstreetmap.org/search?format=json&limit=8&viewbox=%s&bounded=1&addressdetails=1&accept-language=zh",
			viewbox),
		nil,
	)
	if err != nil {
		return nil
	}
	req.Header.Set("User-Agent", "cs-inv-monitor/1.0")

	resp, err := geocodeHTTPClient.Do(req)
	if err != nil {
		logger.Warn("Nearby search failed", zap.Error(err))
		return nil
	}
	defer resp.Body.Close()

	var results []struct {
		DisplayName string `json:"display_name"`
		Lat         string `json:"lat"`
		Lon         string `json:"lon"`
		Address     struct {
			Road        string `json:"road"`
			HouseNumber string `json:"house_number"`
			Suburb      string `json:"suburb"`
			Neighbourhood string `json:"neighbourhood"`
		} `json:"address"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&results); err != nil {
		logger.Warn("Nearby search parse failed", zap.Error(err))
		return nil
	}

	var nearby []NearbyAddress
	seen := make(map[string]bool)
	for _, r := range results {
		// 构造简洁地址
		detail := r.Address.Road
		if r.Address.HouseNumber != "" {
			detail = r.Address.Road + r.Address.HouseNumber + "号"
		}
		if detail == "" {
			detail = r.Address.Suburb
		}
		if detail == "" {
			detail = r.Address.Neighbourhood
		}

		// 地点名称：取 display_name 的第一部分
		name := r.DisplayName
		if idx := strings.Index(r.DisplayName, ","); idx > 0 {
			name = strings.TrimSpace(r.DisplayName[:idx])
		}

		// 去重
		key := name + "|" + detail
		if seen[key] {
			continue
		}
		seen[key] = true

		rLat, _ := strconv.ParseFloat(r.Lat, 64)
		rLng, _ := strconv.ParseFloat(r.Lon, 64)

		nearby = append(nearby, NearbyAddress{
			Name:   name,
			Detail: detail,
			Lat:    rLat,
			Lng:    rLng,
		})
	}

	return nearby
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
