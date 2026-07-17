package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

var geocodeHTTPClient = &http.Client{Timeout: 5 * time.Second}

// geocodeAddress 调用高德地理编码 API，将省/市/区转换为经纬度
func geocodeAddress(province, city, district, amapKey string) (float64, float64, error) {
	if amapKey == "" {
		return 0, 0, fmt.Errorf("amap api key not configured")
	}

	address := province + city + district
	resp, err := geocodeHTTPClient.Get(fmt.Sprintf(
		"https://restapi.amap.com/v3/geocode/geo?address=%s&key=%s",
		url.QueryEscape(address), amapKey,
	))
	if err != nil {
		logger.Warn("Geocode API request failed", zap.String("address", address), zap.Error(err))
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
		logger.Warn("Failed to parse geocode response", zap.Error(err))
		return 0, 0, err
	}
	if result.Status != "1" || len(result.Geocodes) == 0 {
		logger.Warn("Geocode returned no result", zap.String("address", address), zap.String("status", result.Status))
		return 0, 0, fmt.Errorf("geocode failed or no result for address: %s", address)
	}

	parts := strings.Split(result.Geocodes[0].Location, ",")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid location format: %s", result.Geocodes[0].Location)
	}
	lng, _ := strconv.ParseFloat(parts[0], 64)
	lat, _ := strconv.ParseFloat(parts[1], 64)

	logger.Info("Geocode success", zap.String("address", address), zap.Float64("lat", lat), zap.Float64("lng", lng))
	return lat, lng, nil
}
