// Package usage owns range semantics and query orchestration.
package usage

import "time"

// Clock abstracts time.Now for testability.
type Clock interface {
	Now() time.Time
}

type wallClock struct{}

func NewWallClock() Clock { return wallClock{} }

func (wallClock) Now() time.Time { return time.Now() }

type fixedClock struct{ t time.Time }

// NewFixedClock is a test helper.
func NewFixedClock(t time.Time) Clock { return fixedClock{t} }

func (c fixedClock) Now() time.Time { return c.t }
