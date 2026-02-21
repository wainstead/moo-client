package main

import (
	"flag"
	"log"
	"net"
	"net/http"
	"time"

	"moo-client/proxy/internal"
)

const upstreamDialTimeout = 10 * time.Second

func main() {
	mode := flag.String("mode", "local", "proxy listen mode: local or lan")
	listenAddr := flag.String("listen", "", "websocket listen address override")
	upstreamAddr := flag.String("upstream", "127.0.0.1:7777", "upstream MOO TCP address")
	flag.Parse()

	resolvedListenAddr, err := resolveListenAddr(*mode, *listenAddr)
	if err != nil {
		log.Fatalf("resolve listen address: %v", err)
	}

	upstream, err := net.DialTimeout("tcp", *upstreamAddr, upstreamDialTimeout)
	if err != nil {
		log.Fatalf("connect upstream: %v", err)
	}
	defer upstream.Close()

	relay, err := internal.NewRelay(upstream)
	if err != nil {
		log.Fatalf("init relay: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := internal.UpgradeWebSocket(w, r)
		if err != nil {
			http.Error(w, "websocket upgrade failed", http.StatusBadRequest)
			return
		}
		relay.HandleWS(conn)
	})

	go relay.RunUpstreamPump()
	log.Printf("mooproxy listening on %s (mode=%s) with session %s", resolvedListenAddr, *mode, relay.SessionID())
	if err := http.ListenAndServe(resolvedListenAddr, mux); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
