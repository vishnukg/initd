package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestGivenNoCommand_WhenRun_ThenShowsHelp(t *testing.T) {
	// Arrange
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	// Act
	if err := run(nil, &stdout, &stderr); err != nil {
		t.Fatalf("run returned error: %v", err)
	}

	// Assert
	if !strings.Contains(stdout.String(), "Usage:") {
		t.Fatalf("help output missing Usage:\n%s", stdout.String())
	}

	if stderr.Len() != 0 {
		t.Fatalf("stderr should be empty, got:\n%s", stderr.String())
	}
}

func TestGivenVersionCommand_WhenRun_ThenShowsVersion(t *testing.T) {
	// Arrange
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	// Act
	if err := run([]string{"version"}, &stdout, &stderr); err != nil {
		t.Fatalf("run returned error: %v", err)
	}

	// Assert
	if got, want := stdout.String(), "initd dev\n"; got != want {
		t.Fatalf("version output = %q, want %q", got, want)
	}

	if stderr.Len() != 0 {
		t.Fatalf("stderr should be empty, got:\n%s", stderr.String())
	}
}

func TestGivenUnknownCommand_WhenRun_ThenReturnsUsageError(t *testing.T) {
	// Arrange
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	// Act
	if err := run([]string{"nope"}, &stdout, &stderr); err == nil {
		t.Fatal("run returned nil error for unknown command")
	}

	// Assert
	if stdout.Len() != 0 {
		t.Fatalf("stdout should be empty, got:\n%s", stdout.String())
	}

	got := stderr.String()
	if !strings.Contains(got, "Unknown command: nope") {
		t.Fatalf("stderr missing unknown command message:\n%s", got)
	}
	if !strings.Contains(got, "Usage:") {
		t.Fatalf("stderr missing help output:\n%s", got)
	}
}
