package main

import "testing"

func TestResolveListenAddrLocalDefault(t *testing.T) {
	got, err := resolveListenAddr("local", "")
	if err != nil {
		t.Fatalf("resolveListenAddr error = %v", err)
	}
	if got != "127.0.0.1:9000" {
		t.Fatalf("listen addr = %q, want %q", got, "127.0.0.1:9000")
	}
}

func TestResolveListenAddrLanDefault(t *testing.T) {
	got, err := resolveListenAddr("lan", "")
	if err != nil {
		t.Fatalf("resolveListenAddr error = %v", err)
	}
	if got != "0.0.0.0:9000" {
		t.Fatalf("listen addr = %q, want %q", got, "0.0.0.0:9000")
	}
}

func TestResolveListenAddrOverrideWins(t *testing.T) {
	got, err := resolveListenAddr("local", "192.168.1.5:9001")
	if err != nil {
		t.Fatalf("resolveListenAddr error = %v", err)
	}
	if got != "192.168.1.5:9001" {
		t.Fatalf("listen addr = %q, want %q", got, "192.168.1.5:9001")
	}
}

func TestResolveListenAddrInvalidMode(t *testing.T) {
	_, err := resolveListenAddr("bad", "")
	if err == nil {
		t.Fatalf("expected error for invalid mode")
	}
}
