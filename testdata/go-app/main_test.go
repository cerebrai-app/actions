package main

import (
	"strings"
	"testing"
)

func TestVersion(t *testing.T) {
	var out strings.Builder
	if err := run([]string{"version"}, &out); err != nil {
		t.Fatal(err)
	}
	if got, want := out.String(), "go-app "+version+"\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestUsage(t *testing.T) {
	if err := run(nil, &strings.Builder{}); err == nil {
		t.Error("expected a usage error without arguments")
	}
}

// TestSkipped checks that go-test reports skipped tests as notices.
func TestSkipped(t *testing.T) {
	t.Skip("go-test should show this as a notice")
}
