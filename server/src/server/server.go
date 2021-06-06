package server

import (
	"log"
	"net/http"
)

type TLSOpts struct {
	Addr     string
	CertFile string
	KeyFile  string
}

type Opts struct {
	Addr    string
	Handler http.Handler
	TLS     *TLSOpts
}

func redirectToHTTPS(w http.ResponseWriter, r *http.Request) {
	http.Redirect(w, r, "https://"+r.Host+r.RequestURI, http.StatusMovedPermanently)
}

func Start(opts *Opts) error {
	if opts.TLS == nil {
		log.Printf("listening on http://%s", opts.Addr)
		return http.ListenAndServe(opts.Addr, opts.Handler)
	}
	errs := make(chan error)
	go func() {
		log.Printf("listening on https://%s", opts.Addr)
		if err := http.ListenAndServeTLS(
			opts.TLS.Addr,
			opts.TLS.CertFile,
			opts.TLS.KeyFile,
			opts.Handler,
		); err != nil {
			errs <- err
		}
	}()
	go func() {
		log.Printf("listening on http://%s", opts.Addr)
		if err := http.ListenAndServe(
			opts.Addr,
			http.HandlerFunc(redirectToHTTPS),
		); err != nil {
			errs <- err
		}
	}()
	// This will block unless there is an error.
	return <-errs
}
