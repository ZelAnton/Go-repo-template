// Package __GoPackage__ is the sample public API shipped with this template.
//
// Replace it with your real package: rename this file, update the package name
// and doc comment, and implement your public surface. A Go library's package
// files live beside go.mod at the module root (this layout); for a command-line
// program, add cmd/<name>/main.go instead.
package __GoPackage__

import "fmt"

// Greet returns a friendly greeting for name.
func Greet(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}
