package db

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

type DB interface {
	Serve(w http.ResponseWriter, r *http.Request)
	Exec(query string, id string, timestamp *time.Time) error
}

func New(filename string) (*db, error) {
	filename, err := filepath.Abs(filename)
	if err != nil {
		return nil, err
	}
	db := db{
		filename: filename,
		conn:     nil,
	}
	if err := db.init(); err != nil {
		return nil, err
	}
	log.Printf("connected to database at %s\n", filename)
	return &db, nil
}

type db struct {
	// Absolute path
	filename string
	conn     *sql.DB
}

func getCreateJournalQuery() string {
	fields := []string{
		fmt.Sprintf("id TEXT CONSTRAINT id NOT NULL PRIMARY KEY CHECK (TYPEOF(id) IN ('text', 'null')) CHECK (id GLOB '%s') DEFAULT (lower(hex(randomblob(16))))", strings.Repeat("[0-9a-f]", 32)),
		"txn TEXT CONSTRAINT txn NOT NULL CHECK (TYPEOF(txn) IN ('text', 'null')) CHECK (txn != '')",
		"timestamp_ms INTEGER CONSTRAINT timestamp_ms NOT NULL CHECK (TYPEOF(timestamp_ms) IN ('integer', 'null')) CHECK (timestamp_ms > -30610195622000 AND timestamp_ms < 32503708800000)",
	}
	return fmt.Sprintf("CREATE TABLE IF NOT EXISTS journal (%s)", strings.Join(fields, ", "))
}

var createJournalQuery = getCreateJournalQuery()

func (db *db) init() error {
	if db.conn != nil {
		if err := db.conn.Close(); err != nil {
			return err
		}
	}
	if err := os.MkdirAll(filepath.Dir(db.filename), os.ModePerm); err != nil {
		return err
	}
	conn, err := sql.Open("sqlite3", db.filename)
	if err != nil {
		return err
	}
	if _, err := conn.Exec(createJournalQuery); err != nil {
		return err
	}
	db.conn = conn
	return nil
}

func (db *db) Serve(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, db.filename)
}

func (db *db) Exec(query string, id string, timestamp *time.Time) (err error) {
	txn, err := db.conn.Begin()
	if err != nil {
		return err
	}
	finished := false
	defer func() {
		if finished {
			return
		} else if err2 := txn.Rollback(); err2 != nil {
			err = fmt.Errorf("%w; %s", err, err2.Error())
		}
	}()
	if _, err := txn.Exec(query); err != nil {
		return err
	}
	if _, err := txn.Exec(
		"INSERT INTO journal VALUES (?, ?, ?)",
		id,
		query,
		timestamp.UnixNano()/int64(time.Millisecond),
	); err != nil {
		return err
	}
	if err := txn.Commit(); err != nil {
		return err
	} else {
		finished = true
	}
	return nil
}
