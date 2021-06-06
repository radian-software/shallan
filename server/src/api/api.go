package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"time"

	"github.com/golang/gddo/httputil/header"
	"github.com/gorilla/mux"
	"github.com/raxod502/shallan/src/db"
	"github.com/raxod502/shallan/src/util"
)

type API struct {
	DB db.DB
}

type errRes struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, src interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(src)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, &errRes{Error: err.Error()})
}

// https://www.alexedwards.net/blog/how-to-properly-parse-a-json-request-body
func readJSON(w http.ResponseWriter, r *http.Request, dst interface{}) bool {
	if value, _ := header.ParseValueAndParams(r.Header, "Content-Type"); value != "application/json" {
		got := value
		if got == "" {
			got = "none"
		}
		writeError(
			w,
			http.StatusUnsupportedMediaType,
			fmt.Errorf("Expected Content-Type of application/json, got %s", got),
		)
		return false
	}
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(&dst); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return false
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		writeError(w, http.StatusBadRequest, errors.New("Request body contains multiple JSON objects"))
		return false
	}
	return true
}

var idRegexp = regexp.MustCompile(`^[0-9a-f]{32}$`)

func validateId(id string) error {
	if !idRegexp.MatchString(id) {
		return fmt.Errorf("Malformed UUID: %s", id)
	}
	return nil
}

type dbPatchReq struct {
	Txns []struct {
		Id          string `json:"id"`
		Txn         string `json:"txn"`
		TimestampMs int64  `json:"timestampMs"`
	} `json:"txns"`
}

type dbPatchResTxn struct {
	Id        string `json:"id"`
	Attempted *bool  `json:"attempted"`
	Succeeded *bool  `json:"succeeded,omitempty"`
	Error     string `json:"error,omitempty"`
}

type dbPatchRes struct {
	Error *string         `json:"error,omitempty"`
	Txns  []dbPatchResTxn `json:"txns"`
}

func (api *API) dbPatch(w http.ResponseWriter, r *http.Request) {
	req := dbPatchReq{}
	if ok := readJSON(w, r, &req); !ok {
		return
	}
	res := dbPatchRes{Txns: []dbPatchResTxn{}}
	for _, txn := range req.Txns {
		if err := validateId(txn.Id); err != nil {
			writeError(w, http.StatusUnprocessableEntity, err)
			return
		}
		if txn.Txn == "" {
			writeError(
				w,
				http.StatusUnprocessableEntity,
				errors.New("missing field 'txn'"),
			)
			return
		}
		if txn.TimestampMs == 0 {
			writeError(
				w,
				http.StatusUnprocessableEntity,
				errors.New("missing field 'timestampMs'"),
			)
			return
		}
	}
	skipFollowing := false
	for _, txn := range req.Txns {
		timestamp := time.Unix(0, txn.TimestampMs*int64(time.Millisecond))
		if skipFollowing {
			res.Txns = append(res.Txns, dbPatchResTxn{
				Id:        txn.Id,
				Attempted: util.BoolPtr(false),
			})
		} else if err := api.DB.Exec(txn.Txn, txn.Id, &timestamp); err != nil {
			res.Txns = append(res.Txns, dbPatchResTxn{
				Id:        txn.Id,
				Attempted: util.BoolPtr(true),
				Succeeded: util.BoolPtr(false),
				Error:     err.Error(),
			})
			skipFollowing = true
		} else {
			res.Txns = append(res.Txns, dbPatchResTxn{
				Id:        txn.Id,
				Attempted: util.BoolPtr(true),
				Succeeded: util.BoolPtr(true),
			})
		}
	}
	writeJSON(w, http.StatusOK, res)
}

func (api *API) Handler() http.Handler {
	r := mux.NewRouter()
	r.HandleFunc("/api/v1/db", api.dbPatch).Methods("PATCH")
	return r
}
