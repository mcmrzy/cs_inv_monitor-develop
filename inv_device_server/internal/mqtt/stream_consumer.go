package mqtt

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	streamKey    = "device:stream"
	deadStreamKey = "device:stream:dead"
	maxStreamLen = 100000
)

func PublishToStream(rdb *redis.Client, data []byte, sn string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	return rdb.XAdd(ctx, &redis.XAddArgs{
		Stream: streamKey,
		MaxLen: maxStreamLen,
		Approx: true,
		Values: map[string]interface{}{
			"sn":   sn,
			"data": string(data),
		},
	}).Err()
}
