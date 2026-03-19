package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/alecthomas/kong"
	"github.com/raxod502/shallan/src/api"
	"github.com/raxod502/shallan/src/db"
	"github.com/raxod502/shallan/src/server"
)

var cli struct {
	Port        int    `help:"Port to listen for HTTP on." default:"80"`
	Host        string `help:"Interface to bind to." default:"0.0.0.0"`
	TLS         bool   `help:"Enable TLS (requires --tls-cert-file, --tls-key-file)." default:"false"`
	TLSPort     int    `help:"Port to listen for HTTPS on." default:"443"`
	TLSCertFile string `help:"TLS certificate file to use."`

	TLSKeyFile string `help:"TLS private key file to use."`
	Database   string `help:"SQLite database to use." default:"/etc/shallan/library.sqlite3"`
}

func run() error {
	var tlsOpts *server.TLSOpts
	if cli.TLS {
		if cli.TLSCertFile == "" || cli.TLSKeyFile == "" {
			return errors.New("cannot specify --tls without --tls-cert-file and --tls-key-file")
		}
		tlsOpts = &server.TLSOpts{
			Addr:     fmt.Sprintf("%s:%d", cli.Host, cli.TLSPort),
			CertFile: cli.TLSCertFile,
			KeyFile:  cli.TLSKeyFile,
		}
	}
	db, err := db.New(cli.Database)
	if err != nil {
		return err
	}
	api := api.API{DB: db}
	return server.Start(&server.Opts{
		Addr:    fmt.Sprintf("%s:%d", cli.Host, cli.Port),
		Handler: api.Handler(),
		TLS:     tlsOpts,
	})
}

func main() {
	log.SetPrefix("[shalland] ")
	kong.Parse(&cli)
	if err := run(); err != nil {
		log.Fatalln(err)
	}
}
