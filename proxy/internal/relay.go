package internal

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log"
	"net"
	"os"
	"strconv"
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
	nextClientID uint64
	trace        bool
}

type client struct {
	conn *wsConn
	send chan outbound
	id   uint64
}

type outbound struct {
	opcode byte
	data   []byte
}

func NewRelay(upstream net.Conn) (*Relay, error) {
	return newRelayWithBufferCapacity(upstream, 1<<20)
}

func newRelayWithBufferCapacity(upstream net.Conn, bufferCapacity int) (*Relay, error) {
	sid, err := newSessionID()
	if err != nil {
		return nil, err
	}

	return &Relay{
		sessionID: sid,
		upstream:  upstream,
		clients:   map[*client]struct{}{},
		buffer:    newRingBuffer(bufferCapacity),
		trace:     os.Getenv("MOO_PROXY_TRACE") == "1",
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
			startOffset := r.streamOffset
			r.streamOffset += uint64(len(chunk))
			endOffset := r.streamOffset
			r.buffer.Append(chunk)
			oldestOffset := r.streamOffset - uint64(r.buffer.length)
			r.mu.Unlock()

			r.tracef("upstream read bytes=%d start_offset=%d end_offset=%d oldest_offset=%d", len(chunk), startOffset, endOffset, oldestOffset)
			r.broadcast(outbound{opcode: opBinary, data: append([]byte("DATA "), chunk...)})
		}
		if err != nil {
			r.tracef("upstream read stopped: %v", err)
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
	r.tracef("ws client=%d attach", c.id)
	defer func() {
		r.tracef("ws client=%d detach", c.id)
		r.removeClient(c)
	}()

	go c.conn.writeLoop(c.send)
	c.send <- outbound{opcode: opText, data: []byte("WELCOME " + r.sessionID)}

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
		r.tracef("ws client=%d HELLO", c.id)
		return nil
	case line == "PING":
		r.tracef("ws client=%d PING", c.id)
		c.send <- outbound{opcode: opText, data: []byte("PONG")}
		return nil
	case strings.HasPrefix(line, "SEND "):
		payload := []byte(strings.TrimPrefix(line, "SEND ") + "\n")
		r.tracef("ws client=%d SEND bytes=%d", c.id, len(payload))
		return r.sendUpstream(payload)
	case strings.HasPrefix(line, "RESUME "):
		offsetStr := strings.TrimSpace(strings.TrimPrefix(line, "RESUME "))
		offset, err := strconv.ParseUint(offsetStr, 10, 64)
		if err != nil {
			return errors.New("invalid resume offset")
		}
		oldestOffset, streamOffset := r.offsetWindow()
		missing := r.bufferFromOffset(offset)
		r.tracef("ws client=%d RESUME requested_offset=%d oldest_offset=%d stream_offset=%d replay_bytes=%d", c.id, offset, oldestOffset, streamOffset, len(missing))
		if len(missing) > 0 {
			c.send <- outbound{opcode: opBinary, data: append([]byte("DATA "), missing...)}
		}
		return nil
	default:
		return nil
	}
}

func (r *Relay) bufferFromOffset(offset uint64) []byte {
	r.mu.RLock()
	snapshot := r.buffer.Snapshot()
	streamOffset := r.streamOffset
	r.mu.RUnlock()

	if len(snapshot) == 0 {
		return nil
	}
	if offset >= streamOffset {
		return nil
	}

	oldestOffset := streamOffset - uint64(len(snapshot))
	if offset <= oldestOffset {
		return snapshot
	}

	start := int(offset - oldestOffset)
	return snapshot[start:]
}

func (r *Relay) offsetWindow() (uint64, uint64) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.streamOffset - uint64(r.buffer.length), r.streamOffset
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
			log.Printf("dropping websocket client: send buffer full")
			go r.removeClient(c)
		}
	}
}

func (r *Relay) addClient(c *client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.nextClientID++
	c.id = r.nextClientID
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

	r.tracef("upstream down; closing_clients=%d", len(clients))
	for _, c := range clients {
		_ = c.conn.writeClose(1001, "upstream disconnected")
		_ = c.conn.close()
	}
}

func (r *Relay) tracef(format string, args ...any) {
	if r.trace {
		log.Printf("relay trace: "+format, args...)
	}
}

func newSessionID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
