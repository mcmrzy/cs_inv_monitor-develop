package handler

import (
	"context"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var db *pgxpool.Pool

func SetDB(pool *pgxpool.Pool) {
	db = pool
}

func GetDB() *pgxpool.Pool {
	return db
}

func parseID(s string) int64 {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0
	}
	return id
}

func bgCtx() context.Context {
	ctx, _ := context.WithTimeout(context.Background(), 5*time.Second)
	return ctx
}

func parseInt(s string) int {
	v, _ := strconv.Atoi(s)
	return v
}
