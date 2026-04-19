// Package log wraps log/slog with helpers tuned for the versioning pipe's
// existing operator-readable output. The default handler writes plain text
// to stdout so the bats black-box tests keep matching on banner strings.
//
// Design notes:
//   - Section / Success / Warn / Error emit the same ASCII decorations the
//     bash scripts use (========== banners, ✓, ⚠️, ERROR:). These strings are
//     part of the contract — bats tests grep for them verbatim.
//   - Info forwards structured attrs to slog so future observability work
//     can swap the handler without touching callers.
package log

import (
	"fmt"
	"io"
	"log/slog"
	"os"
)

const bannerRule = "=========================================="

var (
	handler slog.Handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	logger               = slog.New(handler)
	stdout  io.Writer    = os.Stdout
	stderr  io.Writer    = os.Stderr
)

// SetOutput redirects the plain-text banner output. Mainly useful for tests.
func SetOutput(out, err io.Writer) {
	stdout = out
	stderr = err
}

// WithHandler swaps the underlying slog handler. Lets callers opt into JSON
// or a custom sink without reworking the banner helpers.
func WithHandler(h slog.Handler) {
	handler = h
	logger = slog.New(h)
}

// Errors from stdout/stderr writes are intentionally ignored — if the
// terminal or captured buffer is broken, there is no useful recovery. Keeping
// the signatures void matches what bash `echo` offered callers.

// Section prints a boxed banner identical to the bash log banners.
func Section(title string) {
	_, _ = fmt.Fprintln(stdout, bannerRule)
	_, _ = fmt.Fprintf(stdout, "  %s\n", title)
	_, _ = fmt.Fprintln(stdout, bannerRule)
}

// Info logs a plain informational line and forwards to slog for structured sinks.
func Info(msg string, attrs ...any) {
	_, _ = fmt.Fprintln(stdout, msg)
	logger.Info(msg, attrs...)
}

// Success prints a success marker matching the bash output.
func Success(msg string) {
	_, _ = fmt.Fprintf(stdout, "✓ %s\n", msg)
}

// Warn prints a warning marker matching the bash output.
func Warn(msg string) {
	_, _ = fmt.Fprintf(stderr, "⚠️  %s\n", msg)
}

// Error prints an error marker. The err, when non-nil, is appended after a colon.
func Error(msg string, err error) {
	if err != nil {
		_, _ = fmt.Fprintf(stderr, "ERROR: %s: %v\n", msg, err)
		return
	}
	_, _ = fmt.Fprintf(stderr, "ERROR: %s\n", msg)
}

// Plain writes a raw line to stdout. Use when the bash script emits an
// un-decorated echo and we must preserve the string verbatim.
func Plain(msg string) {
	_, _ = fmt.Fprintln(stdout, msg)
}
