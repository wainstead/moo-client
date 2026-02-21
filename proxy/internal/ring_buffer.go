package internal

// ringBuffer stores the latest N bytes appended to it.
type ringBuffer struct {
	buf      []byte
	start    int
	length   int
	capacity int
}

func newRingBuffer(capacity int) *ringBuffer {
	return &ringBuffer{
		buf:      make([]byte, capacity),
		capacity: capacity,
	}
}

func (r *ringBuffer) Append(p []byte) {
	for _, b := range p {
		if r.length < r.capacity {
			idx := (r.start + r.length) % r.capacity
			r.buf[idx] = b
			r.length++
			continue
		}
		r.buf[r.start] = b
		r.start = (r.start + 1) % r.capacity
	}
}

func (r *ringBuffer) Snapshot() []byte {
	if r.length == 0 {
		return nil
	}
	out := make([]byte, r.length)
	first := minInt(r.length, r.capacity-r.start)
	copy(out, r.buf[r.start:r.start+first])
	if first < r.length {
		copy(out[first:], r.buf[:r.length-first])
	}
	return out
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
