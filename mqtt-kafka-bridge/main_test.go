package main

import (
	"sync"
	"testing"
	"time"
)

func TestStats_ConcurrentSafety(t *testing.T) {
	var s stats
	const goroutines = 1000

	var wg sync.WaitGroup
	wg.Add(goroutines * 3)

	// Concurrent incIn
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incIn()
		}()
	}

	// Concurrent incOut
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incOut(1)
		}()
	}

	// Concurrent incErr
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			s.incErr()
		}()
	}

	wg.Wait()

	if got := s.messagesIn.Load(); got != goroutines {
		t.Errorf("messagesIn = %d, want %d", got, goroutines)
	}
	if got := s.messagesOut.Load(); got != goroutines {
		t.Errorf("messagesOut = %d, want %d", got, goroutines)
	}
	if got := s.errors.Load(); got != goroutines {
		t.Errorf("errors = %d, want %d", got, goroutines)
	}

	// Verify lastMessageAt was set
	lma := s.lastMessageAt.Load()
	if lma == nil {
		t.Error("lastMessageAt should not be nil after incIn")
	} else {
		ts := lma.(time.Time)
		if ts.IsZero() {
			t.Error("lastMessageAt should not be zero after incIn")
		}
	}
}
