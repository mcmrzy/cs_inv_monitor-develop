package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

func main() {
	apiURL := flag.String("url", "http://localhost:8080", "API gateway URL")
	token := flag.String("token", "", "JWT token for Authorization header")
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
					start := time.Now()
					req, _ := http.NewRequest("GET",
						*apiURL+"/api/v1/device/"+sn+"/online",
						nil,
					)
					if *token != "" {
						req.Header.Set("Authorization", "Bearer "+*token)
					}
					resp, err := client.Do(req)
					lat := time.Since(start).Milliseconds()

					atomic.AddInt64(&totalSent, 1)
					atomic.AddInt64(&totalLatMs, lat)

					if err != nil {
						atomic.AddInt64(&totalErr, 1)
						continue
					}
					io.Copy(io.Discard, resp.Body)
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
