package internal

import "testing"

// RFC 6455 test vector: key "dGhlIHNhbXBsZSBub25jZQ==" -> accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
func TestComputeAcceptKey(t *testing.T) {
	key := "dGhlIHNhbXBsZSBub25jZQ=="
	got := computeAcceptKey(key)
	want := "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
	if got != want {
		t.Fatalf("computeAcceptKey(%q) = %q, want %q", key, got, want)
	}
}

func TestHeaderContainsToken(t *testing.T) {
	tests := []struct {
		name   string
		header string
		token  string
		want   bool
	}{
		{"single upgrade", "Upgrade", "upgrade", true},
		{"lowercase", "upgrade", "upgrade", true},
		{"comma list", "keep-alive, Upgrade", "upgrade", true},
		{"missing", "keep-alive", "upgrade", false},
		{"empty", "", "upgrade", false},
		{"websocket in upgrade", "websocket", "websocket", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := headerContainsToken(tt.header, tt.token)
			if got != tt.want {
				t.Errorf("headerContainsToken(%q, %q) = %v, want %v", tt.header, tt.token, got, tt.want)
			}
		})
	}
}
