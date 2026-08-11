package main

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"strings"
	"sync"
)

const (
	opText   = 0x1
	opBinary = 0x2
	opClose  = 0x8
	opPing   = 0x9
	opPong   = 0xA
)

type wsClient struct {
	conn net.Conn
	r    *bufio.Reader
	mu   sync.Mutex
}

func main() {
	wsURL := os.Getenv("WS_URL")
	if wsURL == "" {
		wsURL = "ws://127.0.0.1:9000/ws"
	}

	c, err := dialWS(wsURL)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect:", err)
		os.Exit(1)
	}
	defer c.conn.Close()

	fmt.Println("Connected:", wsURL)
	fmt.Println("Type protocol lines (e.g., HELLO test-session, RESUME 0, SEND connect guest, PING)")

	go func() {
		for {
			op, p, err := c.readFrame()
			if err != nil {
				fmt.Fprintln(os.Stderr, "read:", err)
				os.Exit(1)
			}
			switch op {
			case opText, opBinary:
				fmt.Println(string(p))
			case opPing:
				_ = c.writeFrame(opPong, p)
			case opClose:
				fmt.Println("server closed connection")
				os.Exit(0)
			}
		}
	}()

	s := bufio.NewScanner(os.Stdin)
	for s.Scan() {
		line := s.Text()
		if err := c.writeFrame(opText, []byte(line+"\n")); err != nil {
			fmt.Fprintln(os.Stderr, "write:", err)
			os.Exit(1)
		}
	}
	if s.Err() != nil {
		fmt.Fprintln(os.Stderr, "stdin:", s.Err())
	}
}

func dialWS(raw string) (*wsClient, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	if u.Scheme != "ws" {
		return nil, errors.New("only ws:// is supported")
	}
	host := u.Host
	if !strings.Contains(host, ":") {
		host += ":80"
	}
	path := u.Path
	if path == "" {
		path = "/"
	}

	conn, err := net.Dial("tcp", host)
	if err != nil {
		return nil, err
	}
	r := bufio.NewReader(conn)

	keyBytes := make([]byte, 16)
	if _, err := rand.Read(keyBytes); err != nil {
		_ = conn.Close()
		return nil, err
	}
	key := base64.StdEncoding.EncodeToString(keyBytes)

	req := fmt.Sprintf("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: %s\r\n\r\n", path, u.Host, key)
	if _, err := conn.Write([]byte(req)); err != nil {
		_ = conn.Close()
		return nil, err
	}

	status, err := r.ReadString('\n')
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	if !strings.Contains(status, "101") {
		_ = conn.Close()
		return nil, fmt.Errorf("bad status: %s", strings.TrimSpace(status))
	}

	headers := map[string]string{}
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			_ = conn.Close()
			return nil, err
		}
		line = strings.TrimSpace(line)
		if line == "" {
			break
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			headers[strings.ToLower(strings.TrimSpace(parts[0]))] = strings.TrimSpace(parts[1])
		}
	}

	expected := expectedAccept(key)
	if headers["sec-websocket-accept"] != expected {
		_ = conn.Close()
		return nil, errors.New("invalid Sec-WebSocket-Accept")
	}

	return &wsClient{conn: conn, r: r}, nil
}

func expectedAccept(key string) string {
	h := sha1.New()
	_, _ = h.Write([]byte(key))
	_, _ = h.Write([]byte("258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func (c *wsClient) readFrame() (byte, []byte, error) {
	h := make([]byte, 2)
	if _, err := io.ReadFull(c.r, h); err != nil {
		return 0, nil, err
	}
	opcode := h[0] & 0x0F
	ln := uint64(h[1] & 0x7F)
	masked := (h[1] & 0x80) != 0

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

	var mask []byte
	if masked {
		mask = make([]byte, 4)
		if _, err := io.ReadFull(c.r, mask); err != nil {
			return 0, nil, err
		}
	}

	payload := make([]byte, ln)
	if _, err := io.ReadFull(c.r, payload); err != nil {
		return 0, nil, err
	}
	if masked {
		for i := uint64(0); i < ln; i++ {
			payload[i] ^= mask[i%4]
		}
	}

	return opcode, payload, nil
}

func (c *wsClient) writeFrame(opcode byte, payload []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	h := make([]byte, 0, 14)
	h = append(h, 0x80|opcode)

	ln := len(payload)
	switch {
	case ln <= 125:
		h = append(h, 0x80|byte(ln))
	case ln <= 65535:
		h = append(h, 0x80|126)
		v := make([]byte, 2)
		binary.BigEndian.PutUint16(v, uint16(ln))
		h = append(h, v...)
	default:
		h = append(h, 0x80|127)
		v := make([]byte, 8)
		binary.BigEndian.PutUint64(v, uint64(ln))
		h = append(h, v...)
	}

	mask := make([]byte, 4)
	if _, err := rand.Read(mask); err != nil {
		return err
	}
	h = append(h, mask...)

	masked := make([]byte, len(payload))
	copy(masked, payload)
	for i := range masked {
		masked[i] ^= mask[i%4]
	}

	if _, err := c.conn.Write(h); err != nil {
		return err
	}
	_, err := c.conn.Write(masked)
	return err
}
