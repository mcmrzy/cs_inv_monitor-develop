package service

import (
	"context"
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"sync"
	"time"
)

var bindingSN = regexp.MustCompile(`^[A-Z0-9]{16}$`)
var bindingNonce = regexp.MustCompile(`^[0-9a-f]{32}$`)

type BindingSnapshotReader interface {
	BindingSnapshot(context.Context, string) (string, string, error)
}
type BindingStatePublisher interface {
	PublishBindingState(context.Context, string, []byte) error
}
type BindingQuery struct {
	SN    string `json:"sn"`
	Nonce string `json:"nonce"`
}
type BindingState struct {
	SN        string `json:"sn"`
	State     string `json:"state"`
	Revision  string `json:"revision"`
	Nonce     string `json:"nonce"`
	KeyID     int    `json:"key_id"`
	Signature string `json:"signature"`
}

// Seed is read only from controlled runtime configuration. Blank disables service.
func BindingSigningKey(seedHex string) (ed25519.PrivateKey, error) {
	if seedHex == "" {
		return nil, nil
	}
	seed, err := hex.DecodeString(seedHex)
	if err != nil || len(seed) != ed25519.SeedSize {
		return nil, errors.New("BINDING_SIGNING_KEY_HEX must contain a 32-byte Ed25519 seed")
	}
	key := ed25519.NewKeyFromSeed(seed)
	for i := range seed {
		seed[i] = 0
	}
	return key, nil
}
func ParseBindingQuery(topicSN string, payload []byte) (BindingQuery, error) {
	var envelope struct {
		Data BindingQuery `json:"data"`
	}
	if len(payload) > 512 || !bindingSN.MatchString(topicSN) {
		return BindingQuery{}, errors.New("invalid binding query")
	}
	if err := json.Unmarshal(payload, &envelope); err != nil {
		return BindingQuery{}, errors.New("invalid binding query")
	}
	q := envelope.Data
	if q.SN != topicSN || !bindingNonce.MatchString(q.Nonce) {
		return BindingQuery{}, errors.New("invalid binding query")
	}
	return q, nil
}
func BindingCanonical(s BindingState) []byte {
	return []byte("CSERGY-BINDING-V1\n" + s.SN + "\n" + s.State + "\n" + s.Revision + "\n" + s.Nonce + "\n")
}
func SignBindingState(key ed25519.PrivateKey, q BindingQuery, state, revision string) (BindingState, error) {
	s := BindingState{SN: q.SN, Nonce: q.Nonce, State: state, Revision: revision, KeyID: 1}
	value, err := strconv.ParseUint(revision, 10, 63)
	if len(key) != ed25519.PrivateKeySize || !bindingSN.MatchString(q.SN) || !bindingNonce.MatchString(q.Nonce) ||
		err != nil || strconv.FormatUint(value, 10) != revision || (state != "UNKNOWN" && state != "UNBOUND" && state != "BOUND") ||
		(value == 0 && state != "UNKNOWN") {
		return BindingState{}, errors.New("invalid binding signing input")
	}
	s.Signature = hex.EncodeToString(ed25519.Sign(key, BindingCanonical(s)))
	return s, nil
}

type DeviceBindingStateService struct {
	repo      BindingSnapshotReader
	publisher BindingStatePublisher
	key       ed25519.PrivateKey
	queue     chan BindingQuery
	once      sync.Once
}

func NewDeviceBindingStateService(repo BindingSnapshotReader, publisher BindingStatePublisher, key ed25519.PrivateKey) *DeviceBindingStateService {
	return &DeviceBindingStateService{repo: repo, publisher: publisher, key: append(ed25519.PrivateKey(nil), key...), queue: make(chan BindingQuery, 64)}
}

// Enqueue is bounded and non-blocking; callbacks never access SQL or sign messages.
func (s *DeviceBindingStateService) Enqueue(sn string, payload []byte) bool {
	if len(s.key) != ed25519.PrivateKeySize {
		return false
	}
	q, err := ParseBindingQuery(sn, payload)
	if err != nil {
		return false
	}
	select {
	case s.queue <- q:
		return true
	default:
		return false
	}
}
func (s *DeviceBindingStateService) Start(ctx context.Context) {
	s.once.Do(func() {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case q := <-s.queue:
					job, cancel := context.WithTimeout(ctx, 5*time.Second)
					_ = s.respond(job, q) // Unavailable database/broker is retried by device backoff.
					cancel()
				}
			}
		}()
	})
}
func (s *DeviceBindingStateService) respond(ctx context.Context, q BindingQuery) error {
	state, revision, err := s.repo.BindingSnapshot(ctx, q.SN)
	if err != nil {
		return err
	}
	response, err := SignBindingState(s.key, q, state, revision)
	if err != nil {
		return err
	}
	payload, err := json.Marshal(response)
	if err != nil {
		return fmt.Errorf("encode binding state: %w", err)
	}
	return s.publisher.PublishBindingState(ctx, q.SN, payload)
}
