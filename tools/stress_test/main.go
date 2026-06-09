package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

type DevicePayload struct {
	SN      string                 `json:"sn"`
	Type    string                 `json:"type"`
	Payload map[string]interface{} `json:"payload"`
}

func main() {
	apiURL := flag.String("url", "http://localhost:8080", "API gateway URL")
	numDevices := flag.Int("devices", 1000, "number of simulated devices")
	duration := flag.Duration("duration", 60*time.Second, "test duration")
	interval := flag.Duration("interval", 5*time.Second, "report interval per device")
	flag.Parse()

	fmt.Printf("Stress test: %d devices, %v duration, %v interval\n", *numDevices, *duration, *interval)

	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			MaxIdleConns:        200,
			MaxIdleConnsPerHost: 200,
		},
	}

	var (
		totalSent   int64
		totalOK     int64
		totalErr    int64
		totalLatMs  int64
	)

	ctx := make(chan struct{})
	go func() {
		time.Sleep(*duration)
		close(ctx)
	}()

	var wg sync.WaitGroup
	for i := 0; i < *numDevices; i++ {
		wg.Add(1)
		sn := fmt.Sprintf("STRESS-%06d", i)
		go func(sn string) {
			defer wg.Done()
			ticker := time.NewTicker(*interval)
			defer ticker.Stop()
			for {
				select {
				case <-ctx:
					return
				case <-ticker.C:
					payload := DevicePayload{
						SN:   sn,
						Type: "data/realtime",
						Payload: map[string]interface{}{
							"ac": map[string]interface{}{
								"voltage":  220 + rand.Float64()*20,
								"current":  rand.Float64() * 30,
								"power":    rand.Float64() * 5000,
								"frequency": 50 + rand.Float64()*0.5,
							},
							"energy": map[string]interface{}{
								"daily_pv":     rand.Float64() * 30,
								"total_pv":     rand.Float64() * 10000,
								"runtime_hours": rand.Float64() * 12,
							},
							"sys_status": map[string]interface{}{
								"state":     "normal",
								"fault_code": 0,
								"temp_inv":   35 + rand.Float64()*20,
							},
						},
					}

					body, _ := json.Marshal(payload)
					start := time.Now()
					resp, err := client.Post(
						*apiURL+"/api/v1/device/"+sn+"/telemetry",
						"application/json",
						bytes.NewReader(body),
					)
					lat := time.Since(start).Milliseconds()

					atomic.AddInt64(&totalSent, 1)
					atomic.AddInt64(&totalLatMs, lat)

					if err != nil {
						atomic.AddInt64(&totalErr, 1)
						continue
					}
					resp.Body.Close()
					if resp.StatusCode < 400 {
						atomic.AddInt64(&totalOK, 1)
					} else {
						atomic.AddInt64(&totalErr, 1)
					}
				}
			}
		}(sn)
	}

	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx:
				return
			case <-ticker.C:
				sent := atomic.LoadInt64(&totalSent)
				ok := atomic.LoadInt64(&totalOK)
				errs := atomic.LoadInt64(&totalErr)
				avgLat := int64(0)
				if sent > 0 {
					avgLat = atomic.LoadInt64(&totalLatMs) / sent
				}
				fmt.Printf("[%s] sent=%d ok=%d err=%d avg_latency=%dms\n",
					time.Now().Format("15:04:05"), sent, ok, errs, avgLat)
			}
		}
	}()

	wg.Wait()

	sent := atomic.LoadInt64(&totalSent)
	ok := atomic.LoadInt64(&totalOK)
	errs := atomic.LoadInt64(&totalErr)
	avgLat := int64(0)
	if sent > 0 {
		avgLat = atomic.LoadInt64(&totalLatMs) / sent
	}

	fmt.Println("\n=== Stress Test Results ===")
	fmt.Printf("Total sent:      %d\n", sent)
	fmt.Printf("Successful:      %d\n", ok)
	fmt.Printf("Failed:          %d\n", errs)
	fmt.Printf("Success rate:    %.2f%%\n", float64(ok)/float64(sent)*100)
	fmt.Printf("Avg latency:     %dms\n", avgLat)
	fmt.Printf("Throughput:      %.1f req/s\n", float64(sent)/duration.Seconds())
}
