// Command go-app is a minimal program for testing the reusable Go workflows.
package main

import (
	"fmt"
	"io"
	"os"
)

// version is set at build time with -ldflags "-X main.version=<version>".
var version = "dev"

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "go-app:", err)
		os.Exit(2)
	}
}

func run(args []string, out io.Writer) error {
	if len(args) != 1 || args[0] != "version" {
		return fmt.Errorf("usage: go-app version")
	}
	_, err := fmt.Fprintf(out, "go-app %s\n", version)
	return err
}
