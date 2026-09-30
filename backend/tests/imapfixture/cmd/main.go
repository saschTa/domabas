package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/domabas/domabas/backend/tests/imapfixture"
)

func main() {
	directory := flag.String("directory", "", "private fixture directory")
	ready := flag.String("ready-file", "", "private ready JSON file")
	address := flag.String("addr", "127.0.0.1:0", "TLS listener address")
	flag.Parse()
	fixture, err := imapfixture.Start(*directory, *address)
	if err != nil {
		fmt.Fprintln(os.Stderr, "start disposable IMAP fixture:", err)
		os.Exit(1)
	}
	defer fixture.Close()
	if err = fixture.PublishReady(*ready); err != nil {
		fmt.Fprintln(os.Stderr, "publish fixture readiness:", err)
		os.Exit(1)
	}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	signal.Stop(stop)
}
