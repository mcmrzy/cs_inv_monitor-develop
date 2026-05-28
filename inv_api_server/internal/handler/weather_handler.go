package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type WeatherHandler struct {
	stationService *service.StationService
	httpClient     *http.Client
}

func NewWeatherHandler(stationService *service.StationService) *WeatherHandler {
	return &WeatherHandler{
		stationService: stationService,
		httpClient:     &http.Client{Timeout: 5 * time.Second},
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
		response.BadRequest(c, "invalid station id")
		return
	}

	userID := middleware.GetUserID(c)
	station, err := h.stationService.GetByID(c.Request.Context(), stationID)
	if err != nil || station == nil || station.UserID != userID {
		response.Forbidden(c, "permission denied")
		return
	}

	url := fmt.Sprintf("https://api.open-meteo.com/v1/forecast?latitude=%.6f&longitude=%.6f&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=Asia%%2FShanghai",
		station.Latitude, station.Longitude)

	resp, err := h.httpClient.Get(url)
	if err != nil {
		response.InternalError(c, "weather service unavailable")
		return
	}
	defer resp.Body.Close()

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
		response.InternalError(c, "weather parse error")
		return
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

	response.Success(c, WeatherResponse{
		Icon:        icon,
		Temperature: result.Current.Temperature,
		TempMin:     tempMin,
		TempMax:     tempMax,
		Desc:        desc,
	})
}

func weatherIcon(code int) string {
	switch {
	case code <= 1:
		return "\u2600"
	case code <= 3:
		return "\u26C5"
	case code <= 48:
		return "\u2601"
	case code <= 57:
		return "\U0001F327"
	case code <= 67:
		return "\U0001F328"
	case code <= 77:
		return "\u2744"
	case code <= 82:
		return "\U0001F327"
	default:
		return "\u26C8"
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
