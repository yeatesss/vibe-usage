package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"syscall"
)

type RuntimeInfo struct {
	Port      int    `json:"port"`
	PID       int    `json:"pid"`
	StartedAt string `json:"started_at"`
	Version   string `json:"version"`
	DataDir   string `json:"data_dir"`
}

// WriteRuntimeJSON writes atomically: write to .tmp, then rename.
func WriteRuntimeJSON(path string, r RuntimeInfo) error {
	data, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ReadRuntimeJSON returns (info, ok). ok=false if file missing or malformed.
func ReadRuntimeJSON(path string) (RuntimeInfo, bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return RuntimeInfo{}, false
	}
	var r RuntimeInfo
	if err := json.Unmarshal(raw, &r); err != nil {
		return RuntimeInfo{}, false
	}
	return r, true
}

// IsProcessAlive uses kill(pid, 0) to probe liveness without signalling.
func IsProcessAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	err := syscall.Kill(pid, 0)
	return err == nil
}
