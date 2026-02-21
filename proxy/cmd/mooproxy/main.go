package main

import (
	"flag"
	"log"
	"net"
	"net/http"

	"moo-client/proxy/internal"
)

func main() {
	listenAddr := flag.String("listen", "127.0.0.1:9000", "websocket listen address")
	upstreamAddr := flag.String("upstream", "127.0.0.1:7777", "upstream MOO TCP address")
	flag.Parse()

	upstream, err := net.Dial("tcp", *upstreamAddr)
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
	log.Printf("mooproxy listening on %s with session %s", *listenAddr, relay.SessionID())
	if err := http.ListenAndServe(*listenAddr, mux); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
