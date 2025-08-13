package main

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"

	"github.com/consensys/gnark-crypto/ecc/bn254"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
)

// BN254 field order (same as in key.sh)
var rOrder = func() *big.Int {
	v, _ := new(big.Int).SetString("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001", 16)
	return v
}()

type BN254Key struct {
	Curve   string `json:"curve"`
	PrivHex string `json:"priv_hex"`
	PubHex  string `json:"pub_hex"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage: %s <scalar_value>\n", os.Args[0])
		fmt.Println()
		fmt.Println("Examples:")
		fmt.Println("  go run extract_bn254_key.go 12345")
		fmt.Println("  go run extract_bn254_key.go 0x1a2b3c4d5e6f")
		fmt.Println("  go run extract_bn254_key.go 69")
		fmt.Println()
		fmt.Printf("Note: Scalar must be > 0 and < field order (%s)\n", rOrder.String())
		os.Exit(1)
	}

	scalarInput := os.Args[1]

	// Parse scalar input (supports both decimal and hex)
	var scalar *big.Int
	var ok bool

	if len(scalarInput) > 2 && scalarInput[:2] == "0x" {
		// Hex input
		scalar, ok = new(big.Int).SetString(scalarInput[2:], 16)
		if !ok {
			log.Fatalf("Invalid hex scalar value: %s", scalarInput)
		}
	} else {
		// Decimal input
		scalar, ok = new(big.Int).SetString(scalarInput, 10)
		if !ok {
			log.Fatalf("Invalid decimal scalar value: %s", scalarInput)
		}
	}

	// Validate scalar is in valid range for BN254
	if scalar.Sign() <= 0 || scalar.Cmp(rOrder) >= 0 {
		log.Fatalf("Scalar must be > 0 and < field order (%s)", rOrder.String())
	}

	// Convert scalar to 32-byte representation
	scalarBytes := make([]byte, 32)
	scalarBytesActual := scalar.Bytes()
	copy(scalarBytes[32-len(scalarBytesActual):], scalarBytesActual)

	// Convert to fr.Element for gnark-crypto
	var frScalar fr.Element
	frScalar.SetBigInt(scalar)

	// Get standard BN254 generators for G1 and G2
	_, _, g1Gen, g2Gen := bn254.Generators()

	// Generate G1 public key: privKey * G1_generator
	var pubkeyG1 bn254.G1Affine
	pubkeyG1.ScalarMultiplication(&g1Gen, frScalar.BigInt(new(big.Int)))

	// Generate G2 public key: privKey * G2_generator
	var pubkeyG2 bn254.G2Affine
	pubkeyG2.ScalarMultiplication(&g2Gen, frScalar.BigInt(new(big.Int)))

	// Serialize G1 and G2 public keys
	pubBytesG1 := pubkeyG1.Marshal()
	pubBytesG2 := pubkeyG2.Marshal()

	// Create the key structure (matching key.sh payload format)
	key := BN254Key{
		Curve:   "bn254",
		PrivHex: "0x" + hex.EncodeToString(scalarBytes),
		PubHex:  "0x" + hex.EncodeToString(pubBytesG1),
	}

	// Output the key in JSON format (same as original script)
	keyJSON, err := json.MarshalIndent(key, "", "  ")
	if err != nil {
		log.Fatalf("Failed to marshal JSON: %v", err)
	}

	fmt.Println("Generated BN254 Key:")
	fmt.Println(string(keyJSON))

	// Additional information
	fmt.Printf("\nKey Details:\n")
	fmt.Printf("Private Key (scalar): %s\n", scalar.String())
	fmt.Printf("Private Key (hex): %s\n", key.PrivHex)
	fmt.Printf("Public Key G1 (hex): %s\n", key.PubHex)
	fmt.Printf("Public Key G1 Length: %d bytes\n", len(pubBytesG1))
	fmt.Printf("Public Key G2 (hex): 0x%s\n", hex.EncodeToString(pubBytesG2))
	fmt.Printf("Public Key G2 Length: %d bytes\n", len(pubBytesG2))

	// Decode G1 public key coordinates for EigenLayer format
	if len(pubBytesG1) == 64 {
		g1X := new(big.Int).SetBytes(pubBytesG1[0:32])
		g1Y := new(big.Int).SetBytes(pubBytesG1[32:64])
		fmt.Printf("\n=== G1 Public Key ===\n")
		fmt.Printf("X coordinate: %s\n", g1X.String())
		fmt.Printf("Y coordinate: %s\n", g1Y.String())
		fmt.Printf("X coordinate (hex): 0x%064x\n", g1X)
		fmt.Printf("Y coordinate (hex): 0x%064x\n", g1Y)

		// Decode G2 public key coordinates
		// G2 points have 2 field elements for each coordinate (128 bytes total)
		if len(pubBytesG2) == 128 {
			// G2 X coordinate (2 field elements)
			g2X0 := new(big.Int).SetBytes(pubBytesG2[0:32])
			g2X1 := new(big.Int).SetBytes(pubBytesG2[32:64])
			// G2 Y coordinate (2 field elements)
			g2Y0 := new(big.Int).SetBytes(pubBytesG2[64:96])
			g2Y1 := new(big.Int).SetBytes(pubBytesG2[96:128])

			fmt.Printf("\n=== G2 Public Key ===\n")
			fmt.Printf("X[0] coordinate: %s\n", g2X0.String())
			fmt.Printf("X[1] coordinate: %s\n", g2X1.String())
			fmt.Printf("Y[0] coordinate: %s\n", g2Y0.String())
			fmt.Printf("Y[1] coordinate: %s\n", g2Y1.String())
			fmt.Printf("X[0] coordinate (hex): 0x%064x\n", g2X0)
			fmt.Printf("X[1] coordinate (hex): 0x%064x\n", g2X1)
			fmt.Printf("Y[0] coordinate (hex): 0x%064x\n", g2Y0)
			fmt.Printf("Y[1] coordinate (hex): 0x%064x\n", g2Y1)

			// Format for Solidity/contract usage
			fmt.Printf("\n=== Solidity Format (for contracts) ===\n")
			fmt.Printf("// G1 Point\n")
			fmt.Printf("BN254.G1Point memory pubkeyG1 = BN254.G1Point({\n")
			fmt.Printf("    X: %s,\n", g1X.String())
			fmt.Printf("    Y: %s\n", g1Y.String())
			fmt.Printf("});\n\n")

			fmt.Printf("// G2 Point\n")
			fmt.Printf("BN254.G2Point memory pubkeyG2 = BN254.G2Point({\n")
			fmt.Printf("    X: [%s, %s],\n", g2X0.String(), g2X1.String())
			fmt.Printf("    Y: [%s, %s]\n", g2Y0.String(), g2Y1.String())
			fmt.Printf("});\n")

			// Key data format for KeyRegistrar (complete with G2)
			fmt.Printf("\n=== KeyRegistrar Format (Complete with G1 and G2) ===\n")
			fmt.Printf("bytes memory keyData = abi.encode(\n")
			fmt.Printf("    %s, // g1X\n", g1X.String())
			fmt.Printf("    %s, // g1Y\n", g1Y.String())
			fmt.Printf("    [%s, %s], // g2X\n", g2X0.String(), g2X1.String())
			fmt.Printf("    [%s, %s]  // g2Y\n", g2Y0.String(), g2Y1.String())
			fmt.Printf(");\n")
		}
	}
}
