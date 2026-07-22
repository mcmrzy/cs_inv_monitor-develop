package logger

import "go.uber.org/zap"

var log *zap.Logger

func init() {
	log = zap.NewNop()
}

func Init(cfg zap.Config) error {
	if log != nil {
		_ = log.Sync()
	}
	var err error
	log, err = cfg.Build()
	return err
}

func Info(msg string, fields ...zap.Field) {
	log.Info(msg, fields...)
}

func Error(msg string, fields ...zap.Field) {
	log.Error(msg, fields...)
}

func Fatal(msg string, fields ...zap.Field) {
	log.Fatal(msg, fields...)
}

func Debug(msg string, fields ...zap.Field) {
	log.Debug(msg, fields...)
}

func Warn(msg string, fields ...zap.Field) {
	log.Warn(msg, fields...)
}

func Sync() {
	_ = log.Sync()
}
