// mqtt-load is an isolated MQTT QoS 1 load generator for staging environments.
// It publishes device status messages and exits non-zero when the configured SLO fails.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/url"
	"os"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/eclipse/paho.golang/autopaho"
	"github.com/eclipse/paho.golang/paho"
)

type metrics struct {
	connected  atomic.Int64
	connectErr atomic.Int64
	sent       atomic.Int64
	publishErr atomic.Int64
	mu         sync.Mutex
	latencies  []time.Duration
}

func main() {
	broker := flag.String("broker", "mqtt://127.0.0.1:1883", "isolated MQTT broker URL")
	clients := flag.Int("clients", 100, "concurrent MQTT clients")
	duration := flag.Duration("duration", 30*time.Second, "publish duration")
	interval := flag.Duration("interval", time.Second, "publish interval per client")
	p95SLO := flag.Duration("p95", 200*time.Millisecond, "maximum allowed QoS 1 publish p95")
	maxErrorRate := flag.Float64("max-error-rate", 0.01, "maximum connection/publish error rate")
	flag.Parse()
	if *clients <= 0 || *duration <= 0 || *interval <= 0 {
		fmt.Fprintln(os.Stderr, "clients, duration and interval must be positive")
		os.Exit(2)
	}

	serverURL, err := url.Parse(*broker)
	if err != nil || serverURL.Host == "" {
		fmt.Fprintln(os.Stderr, "invalid broker URL")
		os.Exit(2)
	}
	username := os.Getenv("MQTT_USERNAME")
	password := os.Getenv("MQTT_PASSWORD")

	runCtx, cancel := context.WithTimeout(context.Background(), *duration+15*time.Second)
	defer cancel()
	start := time.Now()
	stopAt := start.Add(*duration)
	var result metrics
	result.latencies = make([]time.Duration, 0, *clients*int(*duration / *interval))

	var wg sync.WaitGroup
	for i := 0; i < *clients; i++ {
		wg.Add(1)
		go runClient(runCtx, i, serverURL, username, password, stopAt, *interval, &result, &wg)
	}
	wg.Wait()

	result.mu.Lock()
	sort.Slice(result.latencies, func(i, j int) bool { return result.latencies[i] < result.latencies[j] })
	latencies := append([]time.Duration(nil), result.latencies...)
	result.mu.Unlock()
	p95 := percentile(latencies, 0.95)
	connected := result.connected.Load()
	connectErr := result.connectErr.Load()
	sent := result.sent.Load()
	publishErr := result.publishErr.Load()
	totalAttempts := connected + connectErr + sent + publishErr
	errorRate := float64(connectErr+publishErr) / float64(max64(totalAttempts, 1))

	fmt.Printf("clients=%d connected=%d connect_errors=%d sent=%d publish_errors=%d p95=%s error_rate=%.4f\n",
		*clients, connected, connectErr, sent, publishErr, p95, errorRate)
	if sent == 0 || connected != int64(*clients) || p95 > *p95SLO || errorRate > *maxErrorRate {
		os.Exit(1)
	}
}

func runClient(ctx context.Context, index int, serverURL *url.URL, username, password string, stopAt time.Time, interval time.Duration, result *metrics, wg *sync.WaitGroup) {
	defer wg.Done()
	clientID := fmt.Sprintf("inv-load-%d-%d", os.Getpid(), index)
	config := autopaho.ClientConfig{
		ServerUrls:                    []*url.URL{serverURL},
		KeepAlive:                     30,
		CleanStartOnInitialConnection: true,
		SessionExpiryInterval:         0,
		ClientConfig: paho.ClientConfig{
			ClientID: clientID,
		},
	}
	if username != "" {
		config.ConnectUsername = username
		config.ConnectPassword = []byte(password)
	}
	manager, err := autopaho.NewConnection(ctx, config)
	if err != nil {
		result.connectErr.Add(1)
		return
	}
	if err := manager.AwaitConnection(ctx); err != nil {
		result.connectErr.Add(1)
		return
	}
	result.connected.Add(1)
	defer func() {
		disconnectCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = manager.Disconnect(disconnectCtx)
	}()

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	sn := fmt.Sprintf("LOAD-%06d", index)
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			if now.After(stopAt) {
				return
			}
			payload, _ := json.Marshal(map[string]interface{}{"online": true, "timestamp": now.UnixMilli()})
			started := time.Now()
			_, err := manager.Publish(ctx, &paho.Publish{QoS: 1, Topic: "cs_inv/" + sn + "/status", Payload: payload})
			if err != nil {
				result.publishErr.Add(1)
				continue
			}
			result.sent.Add(1)
			result.mu.Lock()
			result.latencies = append(result.latencies, time.Since(started))
			result.mu.Unlock()
		}
	}
}

func percentile(values []time.Duration, quantile float64) time.Duration {
	if len(values) == 0 {
		return 0
	}
	index := int(float64(len(values)-1) * quantile)
	return values[index]
}

func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
