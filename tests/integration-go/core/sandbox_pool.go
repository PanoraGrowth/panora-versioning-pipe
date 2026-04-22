package core

import "sync"

// SandboxPool serializes access to individual sandboxes.
// Two scenarios sharing the same sandbox-N run sequentially;
// scenarios on different sandboxes run concurrently.
type SandboxPool struct {
	mu    sync.Mutex
	locks map[string]chan struct{}
}

// NewSandboxPool creates an empty pool.
func NewSandboxPool() *SandboxPool {
	return &SandboxPool{locks: make(map[string]chan struct{})}
}

// Acquire blocks until the caller holds exclusive access to the named sandbox.
func (p *SandboxPool) Acquire(sandbox string) {
	p.mu.Lock()
	ch, ok := p.locks[sandbox]
	if !ok {
		ch = make(chan struct{}, 1)
		p.locks[sandbox] = ch
	}
	p.mu.Unlock()
	ch <- struct{}{}
}

// Release returns exclusive access to the sandbox.
func (p *SandboxPool) Release(sandbox string) {
	p.mu.Lock()
	ch := p.locks[sandbox]
	p.mu.Unlock()
	<-ch
}
