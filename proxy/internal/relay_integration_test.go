package internal

import (
	"bufio"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestRelayHELLOThenResumeReplaysOnlyRequestedBytes(t *testing.T) {
	h := newRelayHarness(t, 64)
	h.emit("alpha\nbeta\n")
	h.waitForOffset(11)

	c := h.connectClient(t)
	defer c.close()
	c.expectWelcome(t)
	c.writeText(t, "HELLO phone\nRESUME 6\n")

	got := c.collectDataUntilIdle(t, 100*time.Millisecond)
	if string(got) != "beta\n" {
		t.Fatalf("replayed bytes = %q, want %q", string(got), "beta\n")
	}
}

func TestRelayDetachReattachKeepsSingleUpstreamAndNoReplayGap(t *testing.T) {
	h := newRelayHarness(t, 128)
	h.emit("login\n")
	h.waitForOffset(6)

	c1 := h.connectClient(t)
	c1.expectWelcome(t)
	c1.writeText(t, "HELLO phone\nRESUME 0\n")
	first := c1.collectDataUntilIdle(t, 100*time.Millisecond)
	if string(first) != "login\n" {
		t.Fatalf("first replay = %q, want %q", string(first), "login\n")
	}
	offset := uint64(len(first))
	c1.close()

	h.emit("sleep1\nsleep2\n")
	h.waitForOffset(20)

	c2 := h.connectClient(t)
	defer c2.close()
	c2.expectWelcome(t)
	c2.writeText(t, "HELLO phone\nRESUME "+uintToString(offset)+"\n")
	missed := c2.collectDataUntilIdle(t, 100*time.Millisecond)
	if string(missed) != "sleep1\nsleep2\n" {
		t.Fatalf("reattach replay = %q, want %q", string(missed), "sleep1\nsleep2\n")
	}

	h.emit("after\n")
	live := c2.collectDataUntilIdle(t, 100*time.Millisecond)
	if string(live) != "after\n" {
		t.Fatalf("live bytes after reattach = %q, want %q", string(live), "after\n")
	}

	c2.writeText(t, "SEND look\n")
	if got := h.readCommand(t); got != "look\n" {
		t.Fatalf("upstream command after reattach = %q, want %q", got, "look\n")
	}
}

func TestRelayDoesNotDeliverLiveDataBeforeResume(t *testing.T) {
	h := newRelayHarness(t, 128)
	h.emit("before\n")
	h.waitForOffset(7)

	c := h.connectClient(t)
	defer c.close()
	c.expectWelcome(t)

	h.emit("during\n")
	h.waitForOffset(14)
	if got := c.collectDataUntilIdle(t, 100*time.Millisecond); len(got) != 0 {
		t.Fatalf("data before resume = %q, want none", string(got))
	}

	c.writeText(t, "HELLO phone\nRESUME 0\n")
	got := c.collectDataUntilIdle(t, 100*time.Millisecond)
	if string(got) != "before\nduring\n" {
		t.Fatalf("data after resume = %q, want %q", string(got), "before\nduring\n")
	}
}

func TestRelayResumeHandlesStaleAndFutureOffsets(t *testing.T) {
	h := newRelayHarness(t, 8)
	h.emit("abcdefghxyz")
	h.waitForOffset(11)

	stale := h.connectClient(t)
	stale.expectWelcome(t)
	stale.writeText(t, "HELLO stale\nRESUME 1\n")
	staleReplay := stale.collectDataUntilIdle(t, 100*time.Millisecond)
	stale.close()
	if string(staleReplay) != "defghxyz" {
		t.Fatalf("stale replay = %q, want %q", string(staleReplay), "defghxyz")
	}

	future := h.connectClient(t)
	defer future.close()
	future.expectWelcome(t)
	future.writeText(t, "HELLO future\nRESUME 12\n")
	futureReplay := future.collectDataUntilIdle(t, 100*time.Millisecond)
	if len(futureReplay) != 0 {
		t.Fatalf("future replay len = %d (%q), want 0", len(futureReplay), string(futureReplay))
	}
}

func TestRelayHandlesMultipleControlLinesInOneFrame(t *testing.T) {
	h := newRelayHarness(t, 64)
	c := h.connectClient(t)
	defer c.close()
	c.expectWelcome(t)

	c.writeText(t, "HELLO browser\nPING\nSEND look\nSEND say hi\n")
	if got := c.readText(t, time.Second); got != "PONG" {
		t.Fatalf("control response = %q, want PONG", got)
	}
	if got := h.readCommand(t); got != "look\n" {
		t.Fatalf("first upstream command = %q, want %q", got, "look\n")
	}
	if got := h.readCommand(t); got != "say hi\n" {
		t.Fatalf("second upstream command = %q, want %q", got, "say hi\n")
	}
}

type relayHarness struct {
	relay        *Relay
	upstreamPeer net.Conn
	upstreamRead *bufio.Reader
}

func newRelayHarness(t *testing.T, bufferCapacity int) *relayHarness {
	t.Helper()

	relaySide, upstreamPeer := net.Pipe()
	relay, err := newRelayWithBufferCapacity(relaySide, bufferCapacity)
	if err != nil {
		t.Fatalf("new relay: %v", err)
	}
	go relay.RunUpstreamPump()

	h := &relayHarness{
		relay:        relay,
		upstreamPeer: upstreamPeer,
		upstreamRead: bufio.NewReader(upstreamPeer),
	}
	t.Cleanup(func() {
		_ = upstreamPeer.Close()
		_ = relaySide.Close()
	})
	return h
}

func (h *relayHarness) connectClient(t *testing.T) *testWSClient {
	t.Helper()

	serverSide, clientSide := net.Pipe()
	serverConn := &wsConn{conn: serverSide, r: bufio.NewReader(serverSide)}
	go h.relay.HandleWS(serverConn)
	return &testWSClient{conn: clientSide, r: bufio.NewReader(clientSide)}
}

func (h *relayHarness) emit(text string) {
	_ = h.upstreamPeer.SetWriteDeadline(time.Now().Add(time.Second))
	_, _ = h.upstreamPeer.Write([]byte(text))
}

func (h *relayHarness) waitForOffset(want uint64) {
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		h.relay.mu.RLock()
		got := h.relay.streamOffset
		h.relay.mu.RUnlock()
		if got >= want {
			return
		}
		time.Sleep(time.Millisecond)
	}
}

func (h *relayHarness) readCommand(t *testing.T) string {
	t.Helper()

	_ = h.upstreamPeer.SetReadDeadline(time.Now().Add(time.Second))
	got, err := h.upstreamRead.ReadString('\n')
	if err != nil {
		t.Fatalf("read upstream command: %v", err)
	}
	return got
}

type testWSClient struct {
	conn net.Conn
	r    *bufio.Reader
	mu   sync.Mutex
}

func (c *testWSClient) expectWelcome(t *testing.T) {
	t.Helper()

	got := c.readText(t, time.Second)
	if !strings.HasPrefix(got, "WELCOME ") {
		t.Fatalf("initial control = %q, want WELCOME", got)
	}
}

func (c *testWSClient) readText(t *testing.T, timeout time.Duration) string {
	t.Helper()

	opcode, payload, err := c.readFrame(timeout)
	if err != nil {
		t.Fatalf("read text frame: %v", err)
	}
	if opcode != opText {
		t.Fatalf("opcode = %d, want text", opcode)
	}
	return string(payload)
}

func (c *testWSClient) writeText(t *testing.T, payload string) {
	t.Helper()
	c.writeFrame(t, opText, []byte(payload))
}

func (c *testWSClient) collectDataUntilIdle(t *testing.T, idle time.Duration) []byte {
	t.Helper()

	var out []byte
	for {
		opcode, payload, err := c.readFrame(idle)
		if err != nil {
			if isTimeout(err) {
				return out
			}
			t.Fatalf("read frame: %v", err)
		}
		if opcode != opBinary {
			continue
		}
		if !strings.HasPrefix(string(payload), "DATA ") {
			t.Fatalf("binary payload = %q, want DATA prefix", string(payload))
		}
		out = append(out, payload[len("DATA "):]...)
	}
}

func (c *testWSClient) readFrame(timeout time.Duration) (byte, []byte, error) {
	_ = c.conn.SetReadDeadline(time.Now().Add(timeout))

	h := make([]byte, 2)
	if _, err := io.ReadFull(c.r, h); err != nil {
		return 0, nil, err
	}

	opcode := h[0] & 0x0F
	ln := uint64(h[1] & 0x7F)
	switch ln {
	case 126:
		v := make([]byte, 2)
		if _, err := io.ReadFull(c.r, v); err != nil {
			return 0, nil, err
		}
		ln = uint64(binary.BigEndian.Uint16(v))
	case 127:
		v := make([]byte, 8)
		if _, err := io.ReadFull(c.r, v); err != nil {
			return 0, nil, err
		}
		ln = binary.BigEndian.Uint64(v)
	}

	payload := make([]byte, ln)
	if _, err := io.ReadFull(c.r, payload); err != nil {
		return 0, nil, err
	}
	return opcode, payload, nil
}

func (c *testWSClient) writeFrame(t *testing.T, opcode byte, payload []byte) {
	t.Helper()
	c.mu.Lock()
	defer c.mu.Unlock()

	header := []byte{0x80 | opcode}
	ln := len(payload)
	switch {
	case ln <= 125:
		header = append(header, 0x80|byte(ln))
	case ln <= 65535:
		header = append(header, 0x80|126)
		v := make([]byte, 2)
		binary.BigEndian.PutUint16(v, uint16(ln))
		header = append(header, v...)
	default:
		header = append(header, 0x80|127)
		v := make([]byte, 8)
		binary.BigEndian.PutUint64(v, uint64(ln))
		header = append(header, v...)
	}

	mask := []byte{0x11, 0x22, 0x33, 0x44}
	header = append(header, mask...)
	masked := append([]byte(nil), payload...)
	for i := range masked {
		masked[i] ^= mask[i%len(mask)]
	}

	_ = c.conn.SetWriteDeadline(time.Now().Add(time.Second))
	if _, err := c.conn.Write(append(header, masked...)); err != nil {
		t.Fatalf("write websocket frame: %v", err)
	}
}

func (c *testWSClient) close() {
	_ = c.conn.Close()
}

func isTimeout(err error) bool {
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout()
}

func uintToString(v uint64) string {
	if v == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	return string(buf[i:])
}
