package internal

import (
	"bufio"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

const defaultWriteWait = 5 * time.Second
const defaultReadWait = 2 * time.Minute
const maxIncomingFramePayload = 1 << 20

const (
	opText   = 0x1
	opBinary = 0x2
	opClose  = 0x8
	opPing   = 0x9
	opPong   = 0xA
)

type wsConn struct {
	conn net.Conn
	r    *bufio.Reader
	mu   sync.Mutex
}

func UpgradeWebSocket(w http.ResponseWriter, r *http.Request) (*wsConn, error) {
	if !headerContainsToken(r.Header.Get("Connection"), "upgrade") || !headerContainsToken(r.Header.Get("Upgrade"), "websocket") {
		return nil, errors.New("not a websocket upgrade")
	}

	key := strings.TrimSpace(r.Header.Get("Sec-WebSocket-Key"))
	if key == "" {
		return nil, errors.New("missing Sec-WebSocket-Key")
	}

	h, ok := w.(http.Hijacker)
	if !ok {
		return nil, errors.New("hijacking not supported")
	}
	conn, rw, err := h.Hijack()
	if err != nil {
		return nil, err
	}

	accept := computeAcceptKey(key)
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
	if _, err := rw.WriteString(resp); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := rw.Flush(); err != nil {
		_ = conn.Close()
		return nil, err
	}

	return &wsConn{conn: conn, r: rw.Reader}, nil
}

func computeAcceptKey(key string) string {
	h := sha1.New()
	_, _ = h.Write([]byte(key))
	_, _ = h.Write([]byte("258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func headerContainsToken(v string, token string) bool {
	for _, part := range strings.Split(strings.ToLower(v), ",") {
		if strings.TrimSpace(part) == token {
			return true
		}
	}
	return false
}

func (c *wsConn) writeLoop(ch <-chan outbound) {
	for msg := range ch {
		_ = c.conn.SetWriteDeadline(time.Now().Add(defaultWriteWait))
		if err := c.writeFrame(msg.opcode, msg.data); err != nil {
			return
		}
	}
}

func (c *wsConn) readFrame() (byte, []byte, error) {
	_ = c.conn.SetReadDeadline(time.Now().Add(defaultReadWait))

	h := make([]byte, 2)
	if _, err := io.ReadFull(c.r, h); err != nil {
		return 0, nil, err
	}

	opcode := h[0] & 0x0F
	masked := (h[1] & 0x80) != 0
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

	if ln > maxIncomingFramePayload {
		return 0, nil, errors.New("frame too large")
	}

	if !masked {
		return 0, nil, errors.New("client frame must be masked")
	}

	mask := make([]byte, 4)
	if _, err := io.ReadFull(c.r, mask); err != nil {
		return 0, nil, err
	}

	payload := make([]byte, ln)
	if _, err := io.ReadFull(c.r, payload); err != nil {
		return 0, nil, err
	}

	for i := uint64(0); i < ln; i++ {
		payload[i] ^= mask[i%4]
	}

	return opcode, payload, nil
}

func (c *wsConn) writeFrame(opcode byte, payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	h := make([]byte, 0, 10)
	h = append(h, 0x80|opcode)

	ln := len(payload)
	switch {
	case ln <= 125:
		h = append(h, byte(ln))
	case ln <= 65535:
		h = append(h, 126)
		v := make([]byte, 2)
		binary.BigEndian.PutUint16(v, uint16(ln))
		h = append(h, v...)
	default:
		h = append(h, 127)
		v := make([]byte, 8)
		binary.BigEndian.PutUint64(v, uint64(ln))
		h = append(h, v...)
	}

	if _, err := c.conn.Write(h); err != nil {
		return err
	}
	_, err := c.conn.Write(payload)
	return err
}

func (c *wsConn) writeClose(code uint16, reason string) error {
	payload := make([]byte, 2+len(reason))
	binary.BigEndian.PutUint16(payload[:2], code)
	copy(payload[2:], []byte(reason))
	return c.writeFrame(opClose, payload)
}

func (c *wsConn) close() error {
	return c.conn.Close()
}
