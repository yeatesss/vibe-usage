package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWriteRuntimeJSON_Atomic(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "runtime.json")
	r := RuntimeInfo{Port: 12345, PID: 99, StartedAt: "2026-04-22T00:00:00+08:00", Version: "x", DataDir: dir}
	require.NoError(t, WriteRuntimeJSON(path, r))

	raw, err := os.ReadFile(path)
	require.NoError(t, err)
	var got RuntimeInfo
	require.NoError(t, json.Unmarshal(raw, &got))
	assert.Equal(t, r, got)

	_, err = os.Stat(path + ".tmp")
	assert.True(t, os.IsNotExist(err))
}

func TestReadRuntimeJSON_PidCheck(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "runtime.json")
	r := RuntimeInfo{Port: 1, PID: os.Getpid(), Version: "x", DataDir: dir,
		StartedAt: "2026-04-22T00:00:00+08:00"}
	require.NoError(t, WriteRuntimeJSON(path, r))

	got, ok := ReadRuntimeJSON(path)
	require.True(t, ok)
	assert.Equal(t, os.Getpid(), got.PID)
	assert.True(t, IsProcessAlive(got.PID))
}
