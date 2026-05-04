// Package main contains the initd command-line entrypoint.
//
// Keep this package focused on CLI concerns: argument dispatch, terminal output,
// and process exit codes. Repo behavior should live in internal packages so it
// can be tested without running the real command.
package main

import (
	"fmt"
	"io"
	"os"
)

const version = "dev"

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		// At the CLI boundary, there is nowhere useful to return this write
		// failure. Internal code still returns errors so tests can assert them.
		_, _ = fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// run is the testable command dispatcher for the CLI.
//
// It receives writers instead of using stdout/stderr directly so unit tests can
// assert output without touching the real terminal.
func run(args []string, stdout io.Writer, stderr io.Writer) error {
	if len(args) == 0 {
		return printHelp(stdout)
	}

	switch args[0] {
	case "help", "-h", "--help":
		return printHelp(stdout)
	case "version", "-v", "--version":
		_, err := fmt.Fprintf(stdout, "initd %s\n", version)
		return err
	default:
		if _, err := fmt.Fprintf(stderr, "Unknown command: %s\n\n", args[0]); err != nil {
			return err
		}
		if err := printHelp(stderr); err != nil {
			return err
		}
		return fmt.Errorf("run %q for usage", "initd help")
	}
}

// printHelp keeps the top-level CLI help in one place.
//
// It returns write errors so linting and tests can catch output failures instead
// of silently ignoring them.
func printHelp(w io.Writer) error {
	_, err := fmt.Fprint(w, `initd manages this machine setup repository.

Usage:
  initd <command>

Commands:
  help      Show this help.
  version   Show the initd CLI version.

The existing Bash setup remains the stable entrypoint during the Go migration.
`)
	return err
}
