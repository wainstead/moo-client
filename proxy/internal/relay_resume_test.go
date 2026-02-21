package internal

import "testing"

func TestBufferFromOffsetWithinWindow(t *testing.T) {
	r := &Relay{buffer: newRingBuffer(8)}
	r.buffer.Append([]byte("abcdef"))
	r.streamOffset = 6

	got := string(r.bufferFromOffset(3))
	if got != "def" {
		t.Fatalf("bufferFromOffset = %q, want %q", got, "def")
	}
}

func TestBufferFromOffsetOlderThanWindow(t *testing.T) {
	r := &Relay{buffer: newRingBuffer(8)}
	r.buffer.Append([]byte("abcdefgh"))
	r.buffer.Append([]byte("xyz"))
	r.streamOffset = 11

	got := string(r.bufferFromOffset(1))
	if got != "defghxyz" {
		t.Fatalf("bufferFromOffset = %q, want %q", got, "defghxyz")
	}
}

func TestBufferFromOffsetAtTip(t *testing.T) {
	r := &Relay{buffer: newRingBuffer(8)}
	r.buffer.Append([]byte("abcdef"))
	r.streamOffset = 6

	got := r.bufferFromOffset(6)
	if len(got) != 0 {
		t.Fatalf("bufferFromOffset len = %d, want 0", len(got))
	}
}

func TestBufferFromOffsetEmptyBuffer(t *testing.T) {
	r := &Relay{buffer: newRingBuffer(8)}
	// buffer never appended to; streamOffset can be 0 or any value
	r.streamOffset = 0
	got := r.bufferFromOffset(0)
	if len(got) != 0 {
		t.Fatalf("bufferFromOffset with empty buffer len = %d, want 0", len(got))
	}
}

func TestBufferFromOffsetBeyondTip(t *testing.T) {
	r := &Relay{buffer: newRingBuffer(8)}
	r.buffer.Append([]byte("abcdef"))
	r.streamOffset = 6
	got := r.bufferFromOffset(7)
	if len(got) != 0 {
		t.Fatalf("bufferFromOffset(7) with streamOffset 6 len = %d, want 0", len(got))
	}
}
