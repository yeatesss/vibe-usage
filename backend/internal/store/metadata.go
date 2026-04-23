package store

import (
	"database/sql"
	"errors"
)

const firstPassKey = "ingest_first_pass_done"

func (s *Store) IsFirstPassDone() (bool, error) {
	var v string
	err := s.db.QueryRow("SELECT v FROM metadata WHERE k = ?", firstPassKey).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return v == "1", nil
}

func (s *Store) MarkFirstPassDone() error {
	_, err := s.db.Exec(
		`INSERT INTO metadata(k, v) VALUES(?, '1')
		 ON CONFLICT(k) DO UPDATE SET v = '1'`,
		firstPassKey,
	)
	return err
}
