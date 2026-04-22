package core

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// TestSandboxPool_SerializesSameSandbox verifies that two goroutines targeting
// the same sandbox cannot overlap: the second one blocks until the first releases.
func TestSandboxPool_SerializesSameSandbox(t *testing.T) {
	t.Parallel()
	pool := NewSandboxPool()

	const sandbox = "sandbox-01"
	var overlap bool
	var inCritical int32 // 1 when a goroutine is inside the critical section

	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			pool.Acquire(sandbox)
			defer pool.Release(sandbox)

			if !atomic.CompareAndSwapInt32(&inCritical, 0, 1) {
				overlap = true // two goroutines inside at the same time
			}
			time.Sleep(30 * time.Millisecond) // hold the lock briefly
			atomic.StoreInt32(&inCritical, 0)
		}()
	}
	wg.Wait()

	if overlap {
		t.Fatal("two goroutines were inside the critical section simultaneously — pool did not serialize")
	}
}

// TestSandboxPool_ParallelDifferentSandboxes verifies that goroutines on distinct
// sandboxes do NOT block each other: total elapsed time ≈ max(individual), not sum.
func TestSandboxPool_ParallelDifferentSandboxes(t *testing.T) {
	t.Parallel()
	pool := NewSandboxPool()

	sandboxes := []string{"sandbox-01", "sandbox-02", "sandbox-03", "sandbox-04", "sandbox-05"}
	const holdTime = 100 * time.Millisecond

	start := time.Now()
	var wg sync.WaitGroup
	for _, sb := range sandboxes {
		wg.Add(1)
		go func(name string) {
			defer wg.Done()
			pool.Acquire(name)
			defer pool.Release(name)
			time.Sleep(holdTime)
		}(sb)
	}
	wg.Wait()
	elapsed := time.Since(start)

	// If serialized, elapsed ≥ 5 × holdTime = 500ms.
	// If truly parallel, elapsed ≈ holdTime + scheduling overhead.
	// Allow 3× to absorb scheduler variance while still catching serialization.
	limit := 3 * holdTime
	if elapsed >= limit {
		t.Fatalf("goroutines on distinct sandboxes appear serialized: elapsed=%s, limit=%s", elapsed, limit)
	}
}

// TestSandboxPool_NoLeakOnRelease documents the release contract:
//   - Normal Acquire→Release: no panic, no leak.
//   - Double Release or Release-without-Acquire: the channel receive blocks forever
//     (it does NOT panic). Callers must never release without a prior acquire.
//
// We test the normal path; the blocking cases are only documented here because
// testing a goroutine that blocks forever would hang the test suite.
func TestSandboxPool_NoLeakOnRelease(t *testing.T) {
	t.Parallel()
	pool := NewSandboxPool()

	// Normal acquire → release must not block or panic.
	done := make(chan struct{})
	go func() {
		pool.Acquire("sandbox-99")
		pool.Release("sandbox-99")
		close(done)
	}()

	select {
	case <-done:
		// expected
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Acquire→Release blocked unexpectedly")
	}

	// Second normal Acquire→Release on the same sandbox must also succeed,
	// confirming the channel is reusable after a full cycle.
	done2 := make(chan struct{})
	go func() {
		pool.Acquire("sandbox-99")
		pool.Release("sandbox-99")
		close(done2)
	}()
	select {
	case <-done2:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("second Acquire→Release blocked — pool channel not reusable")
	}
}
