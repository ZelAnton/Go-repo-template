package __GoPackage__

import (
	"fmt"
	"testing"
)

func TestGreet(t *testing.T) {
	got := Greet("World")
	want := "Hello, World!"
	if got != want {
		t.Errorf("Greet(%q) = %q, want %q", "World", got, want)
	}
}

// ExampleGreet is a runnable example: `go test` checks its printed output against
// the Output comment, and pkg.go.dev renders it as usage documentation.
func ExampleGreet() {
	fmt.Println(Greet("World"))
	// Output: Hello, World!
}
