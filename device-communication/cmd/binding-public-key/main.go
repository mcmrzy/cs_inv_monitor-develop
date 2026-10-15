// Prints the public key only; never prints or writes the signing seed.
package main

import (
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
	"inv-device-server/internal/service"
	"os"
)

func main() {
	key, err := service.BindingSigningKey(os.Getenv("BINDING_SIGNING_KEY_HEX"))
	if err != nil || key == nil {
		fmt.Fprintln(os.Stderr, "Configure BINDING_SIGNING_KEY_HEX with a controlled 32-byte Ed25519 seed before deriving the public key")
		os.Exit(1)
	}
	public := key.Public().(ed25519.PublicKey)
	for i := range key {
		key[i] = 0
	}
	fmt.Println(hex.EncodeToString(public))
}
