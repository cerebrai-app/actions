// Command go-tool is a second program in the go-app module, so the reusable
// Go workflows are tested with more than one main package.
package main

import "fmt"

// version is set at build time with -ldflags "-X main.version=<version>".
var version = "dev"

func main() {
	fmt.Printf("go-tool %s\n", version)
}
