package internal

import "testing"

func TestRingBufferSnapshotInOrder(t *testing.T) {
	r := newRingBuffer(8)
	r.Append([]byte("abc"))
	r.Append([]byte("def"))

	got := string(r.Snapshot())
	if got != "abcdef" {
		t.Fatalf("snapshot = %q, want %q", got, "abcdef")
	}
}

func TestRingBufferOverwriteOldest(t *testing.T) {
	r := newRingBuffer(8)
	r.Append([]byte("abcdefgh"))
	r.Append([]byte("xyz"))

	got := string(r.Snapshot())
	if got != "defghxyz" {
		t.Fatalf("snapshot = %q, want %q", got, "defghxyz")
	}
}
