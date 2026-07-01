package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type WeatherHandler struct {
	stationService *service.StationService
	httpClient     *http.Client
	weatherAPI     string
	amapAPIKey     string
	weatherSource  string
}

func NewWeatherHandler(stationService *service.StationService, weatherAPI, amapAPIKey, weatherSource string) *WeatherHandler {
	return &WeatherHandler{
		stationService: stationService,
		httpClient:     &http.Client{Timeout: 10 * time.Second},
		weatherAPI:     weatherAPI,
		amapAPIKey:     amapAPIKey,
		weatherSource:  weatherSource,
	}
}

type WeatherResponse struct {
	Icon        string  `json:"icon"`
	Temperature float64 `json:"temperature"`
	TempMin     float64 `json:"temp_min"`
	TempMax     float64 `json:"temp_max"`
	Desc        string  `json:"desc"`
}

func (h *WeatherHandler) GetStationWeather(c *gin.Context) {
	stationID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid station id"))
		return
	}

	userID := middleware.GetUserID(c)
	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil || station == nil || station.UserID != userID {
		response.HandleError(c, apperr.Forbidden("permission denied"))
		return
	}

	var weather WeatherResponse
	if h.weatherSource == "amap" && h.amapAPIKey != "" {
		weather, err = h.fetchWeatherFromAmap(station.Latitude, station.Longitude)
	} else {
		tz := station.Timezone
		if tz == "" {
			tz = timezone.AsiaShanghai
		}
		weather, err = h.fetchWeatherFromOpenMeteo(station.Latitude, station.Longitude, tz)
	}

	if err != nil {
		response.HandleError(c, apperr.Internal("weather service unavailable", err))
		return
	}

	response.Success(c, weather)
}

func (h *WeatherHandler) fetchWeatherFromOpenMeteo(lat, lng float64, tz string) (WeatherResponse, error) {
	encodedTz := timezone.EncodeTimezoneForURL(tz)
	url := fmt.Sprintf("%s?latitude=%.6f&longitude=%.6f&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=%s",
		h.weatherAPI, lat, lng, encodedTz)

	logger.Info("Fetching weather from Open-Meteo", zap.String("url", url))

	resp, err := h.httpClient.Get(url)
	if err != nil {
		logger.Error("Open-Meteo API request failed", zap.Error(err))
		return WeatherResponse{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		logger.Error("Open-Meteo API returned non-OK status", zap.Int("status_code", resp.StatusCode))
		return WeatherResponse{}, fmt.Errorf("weather api returned status %d", resp.StatusCode)
	}

	var result struct {
		Current struct {
			Temperature float64 `json:"temperature_2m"`
			WeatherCode int     `json:"weather_code"`
		} `json:"current"`
		Daily struct {
			TempMax []float64 `json:"temperature_2m_max"`
			TempMin []float64 `json:"temperature_2m_min"`
		} `json:"daily"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		logger.Error("Failed to parse Open-Meteo response", zap.Error(err))
		return WeatherResponse{}, err
	}

	icon := weatherIcon(result.Current.WeatherCode)
	desc := weatherDesc(result.Current.WeatherCode)
	tempMin := 0.0
	tempMax := 0.0
	if len(result.Daily.TempMin) > 0 {
		tempMin = result.Daily.TempMin[0]
	}
	if len(result.Daily.TempMax) > 0 {
		tempMax = result.Daily.TempMax[0]
	}

	return WeatherResponse{
		Icon:        icon,
		Temperature: result.Current.Temperature,
		TempMin:     tempMin,
		TempMax:     tempMax,
		Desc:        desc,
	}, nil
}

func (h *WeatherHandler) fetchWeatherFromAmap(lat, lng float64) (WeatherResponse, error) {
	if lat == 0 && lng == 0 {
		logger.Error("Station coordinates are not set", zap.Float64("latitude", lat), zap.Float64("longitude", lng))
		return WeatherResponse{}, fmt.Errorf("station coordinates not set")
	}

	geoUrl := fmt.Sprintf("https://restapi.amap.com/v3/geocode/regeo?location=%.6f,%.6f&key=%s&radius=1000&extensions=all",
		lng, lat, h.amapAPIKey)

	logger.Info("Fetching geocode from Amap", zap.String("url", geoUrl))

	geoResp, err := h.httpClient.Get(geoUrl)
	if err != nil {
		logger.Error("Amap geocode API request failed", zap.Error(err))
		return WeatherResponse{}, err
	}
	defer geoResp.Body.Close()

	if geoResp.StatusCode != http.StatusOK {
		logger.Error("Amap geocode API returned non-OK status", zap.Int("status_code", geoResp.StatusCode))
		return WeatherResponse{}, fmt.Errorf("geocode api returned status %d", geoResp.StatusCode)
	}

	var geoResult struct {
		Status    string `json:"status"`
		Regeocode struct {
			AddressComponent struct {
				City     []string `json:"city"`
				Adcode   string   `json:"adcode"`
				Province string   `json:"province"`
			} `json:"addressComponent"`
		} `json:"regeocode"`
	}

	if err := json.NewDecoder(geoResp.Body).Decode(&geoResult); err != nil {
		logger.Error("Failed to parse Amap geocode response", zap.Error(err))
		return WeatherResponse{}, err
	}

	if geoResult.Status != "1" || geoResult.Regeocode.AddressComponent.Adcode == "" {
		logger.Error("Failed to get city from Amap geocode", zap.String("status", geoResult.Status))
		return WeatherResponse{}, fmt.Errorf("failed to get city from geocode")
	}

	cityAdcode := geoResult.Regeocode.AddressComponent.Adcode
	weatherUrl := fmt.Sprintf("https://restapi.amap.com/v3/weather/weatherInfo?city=%s&key=%s&extensions=all",
		cityAdcode, h.amapAPIKey)

	logger.Info("Fetching weather from Amap", zap.String("url", weatherUrl))

	weatherResp, err := h.httpClient.Get(weatherUrl)
	if err != nil {
		logger.Error("Amap weather API request failed", zap.Error(err))
		return WeatherResponse{}, err
	}
	defer weatherResp.Body.Close()

	if weatherResp.StatusCode != http.StatusOK {
		logger.Error("Amap weather API returned non-OK status", zap.Int("status_code", weatherResp.StatusCode))
		return WeatherResponse{}, fmt.Errorf("weather api returned status %d", weatherResp.StatusCode)
	}

	var weatherResult struct {
		Status    string `json:"status"`
		Forecasts []struct {
			City       string `json:"city"`
			ReportTime string `json:"reporttime"`
			Casts      []struct {
				DayWeather   string `json:"dayweather"`
				NightWeather string `json:"nightweather"`
				DayTemp      string `json:"daytemp"`
				NightTemp    string `json:"nighttemp"`
			} `json:"casts"`
		} `json:"forecasts"`
	}

	if err := json.NewDecoder(weatherResp.Body).Decode(&weatherResult); err != nil {
		logger.Error("Failed to parse Amap weather response", zap.Error(err))
		return WeatherResponse{}, err
	}

	if weatherResult.Status != "1" || len(weatherResult.Forecasts) == 0 || len(weatherResult.Forecasts[0].Casts) == 0 {
		logger.Error("Failed to get weather from Amap", zap.String("status", weatherResult.Status))
		return WeatherResponse{}, fmt.Errorf("failed to get weather data")
	}

	cast := weatherResult.Forecasts[0].Casts[0]
	temp, _ := strconv.ParseFloat(cast.DayTemp, 64)
	tempMax, _ := strconv.ParseFloat(cast.DayTemp, 64)
	tempMin, _ := strconv.ParseFloat(cast.NightTemp, 64)

	desc := cast.DayWeather
	icon := amapWeatherIcon(desc)

	return WeatherResponse{
		Icon:        icon,
		Temperature: temp,
		TempMin:     tempMin,
		TempMax:     tempMax,
		Desc:        desc,
	}, nil
}

func amapWeatherIcon(desc string) string {
	switch {
	case desc == "晴":
		return "\U0001F31E"
	case desc == "多云" || desc == "晴转多云" || desc == "多云转晴":
		return "\U0001F324"
	case desc == "阴":
		return "\U0001F325"
	case strings.Contains(desc, "雨") && strings.Contains(desc, "雪"):
		return "\U0001F328"
	case strings.Contains(desc, "雨"):
		return "\U0001F327"
	case strings.Contains(desc, "雪"):
		return "\U0001F328"
	case strings.Contains(desc, "雷"):
		return "\U0001F329"
	default:
		return "\U0001F31E"
	}
}

func (h *WeatherHandler) getMockWeather() WeatherResponse {
	return WeatherResponse{
		Icon:        "\U0001F31E",
		Temperature: 25.5,
		TempMin:     20.0,
		TempMax:     30.0,
		Desc:        "晴",
	}
}

func weatherIcon(code int) string {
	switch {
	case code <= 1:
		return "\U0001F31E"
	case code <= 3:
		return "\U0001F324"
	case code <= 48:
		return "\U0001F325"
	case code <= 57:
		return "\U0001F327"
	case code <= 67:
		return "\U0001F328"
	case code <= 77:
		return "\U0001F328"
	case code <= 82:
		return "\U0001F327"
	default:
		return "\U0001F329"
	}
}

func weatherDesc(code int) string {
	switch {
	case code <= 1:
		return "晴"
	case code <= 3:
		return "多云"
	case code <= 48:
		return "阴"
	case code <= 57:
		return "小雨"
	case code <= 67:
		return "雨夹雪"
	case code <= 77:
		return "雪"
	case code <= 82:
		return "大雨"
	default:
		return "雷阵雨"
	}
}
