package service

import (
	"context"
	"errors"
	"fmt"
)

type ingestErrorStore interface {
	SaveIngestError(context.Context, string, string, []byte, string, string) error
}

type permanentMessageError struct {
	code string
	err  error
}

func (e *permanentMessageError) Error() string { return e.err.Error() }
func (e *permanentMessageError) Unwrap() error { return e.err }

func permanentMessage(code string, err error) error {
	return &permanentMessageError{code: code, err: err}
}

func asPermanentMessage(err error) (*permanentMessageError, bool) {
	var target *permanentMessageError
	ok := errors.As(err, &target)
	return target, ok
}

type downstreamHTTPError struct {
	status int
	body   string
}

func (e *downstreamHTTPError) Error() string {
	return fmt.Sprintf("internal api status %d: %s", e.status, e.body)
}

func (e *downstreamHTTPError) permanent() bool {
	return e.status >= 400 && e.status < 500
}
