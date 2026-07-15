package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/segmentio/kafka-go"
)

// kafkaMessageReader abstracts a Kafka reader so that service-layer consumers
// can be tested with scripted doubles instead of a live broker connection.
// *kafka.Reader satisfies this interface at runtime.
type kafkaMessageReader interface {
	FetchMessage(ctx context.Context) (kafka.Message, error)
	CommitMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

// ingestErrorStore abstracts the persistent store for ingest errors, allowing
// both *repository.DeviceRepository and test doubles to satisfy the contract.
type ingestErrorStore interface {
	SaveIngestError(ctx context.Context, sn, topic string, payload []byte, code, detail string) error
}

// permanentMessageError wraps an error that can never succeed by retrying.
// Such messages are isolated into device_ingest_errors instead of blocking
// the partition forever.
type permanentMessageError struct {
	code string
	err  error
}

func (e *permanentMessageError) Error() string {
	return fmt.Sprintf("permanent ingest error [%s]: %v", e.code, e.err)
}

func (e *permanentMessageError) Unwrap() error {
	return e.err
}

// permanentMessage wraps err as a permanent ingest error carrying the given
// diagnostic code.  Callers should return the result directly so that the
// consumer loop can detect it via asPermanentMessage and isolate the message.
func permanentMessage(code string, err error) error {
	return &permanentMessageError{code: code, err: err}
}

// asPermanentMessage extracts a *permanentMessageError from err's chain.
// Returns (nil, false) when err is not a permanent error.
func asPermanentMessage(err error) (*permanentMessageError, bool) {
	var pme *permanentMessageError
	if errors.As(err, &pme) {
		return pme, true
	}
	return nil, false
}

// downstreamHTTPError represents a non-2xx response from a downstream HTTP API.
// 4xx responses are treated as permanent (client-side error that will not
// succeed on retry); 5xx responses are transient and retried by the caller.
type downstreamHTTPError struct {
	status int
	body   string
}

func (e *downstreamHTTPError) Error() string {
	if e.body != "" {
		return fmt.Sprintf("downstream HTTP %d: %s", e.status, e.body)
	}
	return fmt.Sprintf("downstream HTTP %d", e.status)
}

// permanent returns true for 4xx responses, which cannot be resolved by
// retrying and should be isolated in device_ingest_errors.
func (e *downstreamHTTPError) permanent() bool {
	return e.status >= 400 && e.status < 500
}
