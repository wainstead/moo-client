package main

import "fmt"

func resolveListenAddr(mode string, listenOverride string) (string, error) {
	if listenOverride != "" {
		return listenOverride, nil
	}

	switch mode {
	case "local":
		return "127.0.0.1:9000", nil
	case "lan":
		return "0.0.0.0:9000", nil
	default:
		return "", fmt.Errorf("invalid mode %q (expected local or lan)", mode)
	}
}
