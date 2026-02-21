package internal

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net"
	"strings"
	"sync"
)

type Relay struct {
	sessionID string
	upstream  net.Conn

	mu           sync.RWMutex
	clients      map[*client]struct{}
	upstreamDown bool
	streamOffset uint64
	buffer       *ringBuffer
	writeMu      sync.Mutex
}

type client struct {
	conn *wsConn
	send chan outbound
}

type outbound struct {
	opcode byte
	data   []byte
}

func NewRelay(upstream net.Conn) (*Relay, error) {
	sid, err := newSessionID()
	if err != nil {
		return nil, err
	}

	return &Relay{
		sessionID: sid,
		upstream:  upstream,
		clients:   map[*client]struct{}{},
		buffer:    newRingBuffer(1 << 20),
	}, nil
}

func (r *Relay) SessionID() string {
	return r.sessionID
}

func (r *Relay) RunUpstreamPump() {
	buf := make([]byte, 4096)
	for {
		n, err := r.upstream.Read(buf)
		if n > 0 {
			chunk := append([]byte(nil), buf[:n]...)

			r.mu.Lock()
			r.streamOffset += uint64(len(chunk))
			r.buffer.Append(chunk)
			r.mu.Unlock()

			r.broadcast(outbound{opcode: opBinary, data: append([]byte("DATA "), chunk...)})
		}
		if err != nil {
			r.markUpstreamDown()
			return
		}
	}
}

func (r *Relay) HandleWS(conn *wsConn) {
	c := &client{
		conn: conn,
		send: make(chan outbound, 32),
	}

	r.addClient(c)
	defer r.removeClient(c)

	go c.conn.writeLoop(c.send)
	c.send <- outbound{opcode: opText, data: []byte("WELCOME " + r.sessionID)}
	if recent := r.latestBuffer(); len(recent) > 0 {
		c.send <- outbound{opcode: opBinary, data: append([]byte("DATA "), recent...)}
	}

	for {
		opcode, payload, err := conn.readFrame()
		if err != nil {
			return
		}

		switch opcode {
		case opPing:
			c.send <- outbound{opcode: opPong, data: payload}
			continue
		case opClose:
			return
		case opText, opBinary:
		default:
			continue
		}

		s := bufio.NewScanner(strings.NewReader(string(payload)))
		for s.Scan() {
			line := s.Text()
			if err := r.handleLine(c, line); err != nil {
				_ = conn.writeClose(1000, err.Error())
				return
			}
		}
	}
}

func (r *Relay) handleLine(c *client, line string) error {
	line = strings.TrimSuffix(line, "\r")
	if line == "" {
		return nil
	}

	switch {
	case strings.HasPrefix(line, "HELLO "):
		return nil
	case line == "PING":
		c.send <- outbound{opcode: opText, data: []byte("PONG")}
		return nil
	case strings.HasPrefix(line, "SEND "):
		return r.sendUpstream([]byte(strings.TrimPrefix(line, "SEND ") + "\n"))
	case strings.HasPrefix(line, "RESUME "):
		return errors.New("resume not available in phase 2")
	default:
		return nil
	}
}

func (r *Relay) latestBuffer() []byte {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.buffer.Snapshot()
}

func (r *Relay) sendUpstream(data []byte) error {
	r.mu.RLock()
	down := r.upstreamDown
	r.mu.RUnlock()
	if down {
		return errors.New("upstream disconnected")
	}

	r.writeMu.Lock()
	defer r.writeMu.Unlock()

	_, err := r.upstream.Write(data)
	if err != nil {
		r.markUpstreamDown()
		return err
	}
	return nil
}

func (r *Relay) broadcast(msg outbound) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for c := range r.clients {
		select {
		case c.send <- msg:
		default:
			go r.removeClient(c)
		}
	}
}

func (r *Relay) addClient(c *client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.clients[c] = struct{}{}
}

func (r *Relay) removeClient(c *client) {
	r.mu.Lock()
	if _, ok := r.clients[c]; ok {
		delete(r.clients, c)
		close(c.send)
	}
	r.mu.Unlock()
	_ = c.conn.close()
}

func (r *Relay) markUpstreamDown() {
	r.mu.Lock()
	if r.upstreamDown {
		r.mu.Unlock()
		return
	}
	r.upstreamDown = true
	clients := make([]*client, 0, len(r.clients))
	for c := range r.clients {
		clients = append(clients, c)
	}
	r.mu.Unlock()

	for _, c := range clients {
		_ = c.conn.writeClose(1001, "upstream disconnected")
		_ = c.conn.close()
	}
}

func newSessionID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
