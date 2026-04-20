package pipeline

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
)

// StageRunner executes a pipeline stage. The Run method is called with the
// bare subcommand name (e.g. "detect-scenario") and a stage label used for
// error wrapping.
type StageRunner interface {
	Run(ctx context.Context, subcommand, stage string) error
}

// SelfExecRunner runs each stage as a sub-process invocation of the currently
// running binary. This matches the bash model (each stage = its own process)
// and keeps error handling + exit-code propagation identical.
//
// stdout and stderr are streamed to the configured writers so the
// orchestrator produces an uninterrupted log like pipe.sh did.
type SelfExecRunner struct {
	// BinaryPath is the absolute path to the binary to re-invoke. When empty,
	// os.Args[0] is used (the currently running binary).
	BinaryPath string
	// Stdout is where each stage's stdout is streamed. Defaults to os.Stdout.
	Stdout io.Writer
	// Stderr is where each stage's stderr is streamed. Defaults to os.Stderr.
	Stderr io.Writer
	// ExtraEnv lets tests inject additional environment entries (KEY=VALUE)
	// without polluting os.Environ. The current process env is always
	// forwarded first.
	ExtraEnv []string
}

// Run executes `<binary> <subcommand>` and wraps any error with the stage
// name. Exit codes are preserved via *exec.ExitError — callers can inspect
// it with errors.As to recover the stage's original code.
func (r *SelfExecRunner) Run(ctx context.Context, subcommand, stage string) error {
	bin := r.BinaryPath
	if bin == "" {
		bin = os.Args[0]
	}

	cmd := exec.CommandContext(ctx, bin, subcommand)
	cmd.Stdout = writerOrDefault(r.Stdout, os.Stdout)
	cmd.Stderr = writerOrDefault(r.Stderr, os.Stderr)
	if len(r.ExtraEnv) > 0 {
		cmd.Env = append(os.Environ(), r.ExtraEnv...)
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("pipeline.%s: %w", stage, err)
	}
	return nil
}

func writerOrDefault(w, def io.Writer) io.Writer {
	if w == nil {
		return def
	}
	return w
}
