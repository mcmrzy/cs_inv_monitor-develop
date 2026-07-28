package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var geocodeHTTPClient = &http.Client{Timeout: 10 * time.Second}

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

	response.Success(c, result)
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
	Province string `json:"province"`
	City     string `json:"city"`
	District string `json:"district"`
	Address  string `json:"address"`
	Country  string `json:"country"`
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
			Country     string `json:"country"`
			State       string `json:"state"`
			Province    string `json:"province"`
			City        string `json:"city"`
			Town        string `json:"town"`
			County      string `json:"county"`
			Suburb      string `json:"suburb"`
			CityDistrict string `json:"city_district"`
			Village     string `json:"village"`
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

	return &ReverseGeocodeResult{
		Province: province,
		City:     city,
		District: district,
		Address:  result.DisplayName,
		Country:  result.Address.Country,
	}, nil
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
