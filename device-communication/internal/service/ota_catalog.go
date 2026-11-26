package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"inv-device-server/pkg/logger"

	"go.uber.org/zap"
)

var catalogSN = regexp.MustCompile(`^[A-Z0-9]{16}$`)
var catalogRequestID = regexp.MustCompile(`^[0-9a-f]{16}$`)

type CatalogQuery struct {
	V         int             `json:"v"`
	Type      string          `json:"type"`
	SN        string          `json:"sn"`
	RequestID string          `json:"request_id"`
	Epoch     uint32          `json:"epoch"`
	Index     uint32          `json:"index"`
	Target    string          `json:"target"`
	Raw       json.RawMessage `json:"-"`
	queuedAt  time.Time
}
type PanelRPCPublisher interface {
	PublishPanelRPC(context.Context, string, []byte) error
}
type FirmwareCatalogService struct {
	apiServer, key string
	publisher      PanelRPCPublisher
	client         *http.Client
	queue          chan CatalogQuery
	once           sync.Once
}

func NewFirmwareCatalogService(apiServer, key string, publisher PanelRPCPublisher) *FirmwareCatalogService {
	return &FirmwareCatalogService{apiServer: strings.TrimRight(apiServer, "/"), key: key, publisher: publisher,
		client: &http.Client{Timeout: 5 * time.Second}, queue: make(chan CatalogQuery, 16)}
}
func ParseCatalogQuery(topicSN string, payload []byte) (CatalogQuery, error) {
	var e struct {
		V    int             `json:"v"`
		Data json.RawMessage `json:"data"`
	}
	if len(payload) > 512 || json.Unmarshal(payload, &e) != nil {
		return CatalogQuery{}, errors.New("invalid catalog query")
	}
	var q CatalogQuery
	if json.Unmarshal(e.Data, &q) != nil || e.V != 1 || q.V != 1 || q.SN != topicSN || !catalogSN.MatchString(q.SN) ||
		!catalogRequestID.MatchString(q.RequestID) {
		return CatalogQuery{}, errors.New("invalid panel query")
	}
	if q.Type != "catalog.query" || q.Target != "esp" || q.Index >= 1000 {
		return CatalogQuery{}, errors.New("invalid catalog query")
	}
	q.Raw = append(json.RawMessage(nil), e.Data...)
	q.queuedAt = time.Now()
	return q, nil
}
func (s *FirmwareCatalogService) Enqueue(sn string, payload []byte) bool {
	q, err := ParseCatalogQuery(sn, payload)
	if err != nil {
		logger.Warn("Panel firmware catalog query rejected", zap.String("sn", sn), zap.Error(err))
		return false
	}
	select {
	case s.queue <- q:
		return true
	default:
		logger.Warn("Panel firmware catalog queue full", zap.String("sn", sn), zap.String("request_id", q.RequestID))
		return false
	}
}
func (s *FirmwareCatalogService) Start(ctx context.Context) {
	s.once.Do(func() {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case q := <-s.queue:
					job, cancel := context.WithTimeout(ctx, 6*time.Second)
					if err := s.respond(job, q); err != nil {
						logger.Warn("Panel firmware catalog MQTT reply failed", zap.String("sn", q.SN), zap.String("request_id", q.RequestID), zap.Error(err))
					}
					cancel()
				}
			}
		}()
	})
}
func catalogFailure(q CatalogQuery) []byte {
	payload, _ := json.Marshal(map[string]interface{}{"v": 1, "action": "catalog", "sn": q.SN, "request_id": q.RequestID, "epoch": q.Epoch, "index": q.Index, "total": 0, "status": "error"})
	return payload
}
func (s *FirmwareCatalogService) respond(ctx context.Context, q CatalogQuery) error {
	payload, err := s.fetch(ctx, q)
	if err != nil {
		logger.Warn("Panel firmware catalog lookup failed", zap.String("sn", q.SN), zap.String("request_id", q.RequestID), zap.Error(err))
		payload = catalogFailure(q)
	}
	// The catalog is local-device initiated; this publishes metadata only.
	// Confirmation and installation remain owned by the physical LCD task.
	return s.publisher.PublishPanelRPC(ctx, q.SN, payload)
}
func (s *FirmwareCatalogService) fetch(ctx context.Context, q CatalogQuery) ([]byte, error) {
	if !q.queuedAt.IsZero() && time.Since(q.queuedAt) > 10*time.Second {
		return nil, errors.New("panel query expired in queue")
	}
	body, _ := json.Marshal(q)
	if len(q.Raw) > 0 {
		body = q.Raw
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiServer+"/api/v1/internal/ota-catalog", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Key", s.key)
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4097))
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("catalog backend HTTP status %d", resp.StatusCode)
	}
	if err != nil || len(raw) > 4096 {
		return nil, errors.New("catalog backend unavailable")
	}
	var envelope struct {
		Code int             `json:"code"`
		Data json.RawMessage `json:"data"`
	}
	if json.Unmarshal(raw, &envelope) != nil || len(envelope.Data) > 1800 {
		return nil, errors.New("invalid catalog response")
	}
	if envelope.Code != 0 {
		return nil, fmt.Errorf("catalog backend returned code %d", envelope.Code)
	}
	var reply struct {
		V      int    `json:"v"`
		Action string `json:"action"`
		SN     string `json:"sn"`
		ID     string `json:"request_id"`
		Epoch  uint32 `json:"epoch"`
		Index  uint32 `json:"index"`
	}
	if json.Unmarshal(envelope.Data, &reply) != nil || reply.V != 1 || reply.Action != "catalog" || reply.SN != q.SN || reply.ID != q.RequestID || reply.Epoch != q.Epoch || reply.Index != q.Index {
		return nil, errors.New("uncorrelated panel response")
	}
	return envelope.Data, nil
}
