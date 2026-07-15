package middleware

import (
	"compress/gzip"
	"io"
	"net/http"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
)

// gzipWriter wraps gin.ResponseWriter with lazy gzip compression.
// It checks Content-Type on the first Write to decide whether to compress.
type gzipWriter struct {
	gin.ResponseWriter
	writer   *gzip.Writer
	gzActive bool
	checked  bool
}

func (w *gzipWriter) ensureChecked() {
	if w.checked {
		return
	}
	w.checked = true
	ct := w.Header().Get("Content-Type")
	if shouldCompress(ct) {
		w.gzActive = true
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Del("Content-Length")
	}
}

func (w *gzipWriter) Write(data []byte) (int, error) {
	w.ensureChecked()
	if w.gzActive {
		return w.writer.Write(data)
	}
	return w.ResponseWriter.Write(data)
}

// WriteHeader intercepts WriteHeader to ensure gzip headers are set before the
// response headers are flushed. This is critical for reverse-proxy scenarios
// where httputil.ReverseProxy may flush headers (via maxLatencyWriter's
// delayedFlush goroutine) before the first Write call reaches gzipWriter.
func (w *gzipWriter) WriteHeader(code int) {
	w.ensureChecked()
	w.ResponseWriter.WriteHeader(code)
}

func (w *gzipWriter) WriteString(s string) (int, error) {
	w.ensureChecked()
	if w.gzActive {
		return w.writer.Write([]byte(s))
	}
	return w.ResponseWriter.WriteString(s)
}

// Flush implements http.Flusher to support SSE and streaming responses.
// ensureChecked is called first so that when a reverse proxy's maxLatencyWriter
// fires a delayedFlush before the first Write, the Content-Encoding header is
// already set and Content-Length is removed before headers are flushed.
func (w *gzipWriter) Flush() {
	w.ensureChecked()
	if w.gzActive {
		w.writer.Flush()
	}
	w.ResponseWriter.Flush()
}

// shouldCompress determines whether the response should be gzip-compressed.
// SSE (text/event-stream), WebSocket upgrades, and binary content types are excluded.
func shouldCompress(contentType string) bool {
	if contentType == "" {
		return true // assume JSON if unknown
	}
	ct := strings.ToLower(contentType)
	switch {
	case strings.Contains(ct, "text/event-stream"):
		return false
	case strings.Contains(ct, "application/json"):
		return true
	case strings.Contains(ct, "text/"):
		return true
	case strings.Contains(ct, "application/javascript"):
		return true
	case strings.Contains(ct, "application/xml"):
		return true
	case strings.Contains(ct, "image/"):
		return false
	case strings.Contains(ct, "video/"):
		return false
	case strings.Contains(ct, "application/zip"):
		return false
	case strings.Contains(ct, "application/gzip"):
		return false
	default:
		return false
	}
}

var gzipWriterPool = sync.Pool{
	New: func() interface{} {
		w, _ := gzip.NewWriterLevel(io.Discard, gzip.DefaultCompression)
		return w
	},
}

// GzipMiddleware returns a Gin middleware that compresses HTTP responses with
// gzip when the client supports it (Accept-Encoding: gzip). It is designed for
// reverse proxy scenarios: the Content-Type is checked lazily on first Write
// so that SSE, WebSocket, and binary responses bypass compression.
func GzipMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip if client doesn't accept gzip
		if !strings.Contains(c.GetHeader("Accept-Encoding"), "gzip") {
			c.Next()
			return
		}

		// Skip WebSocket upgrade requests
		if strings.EqualFold(c.GetHeader("Connection"), "upgrade") {
			c.Next()
			return
		}

		// Skip HEAD requests (no body)
		if c.Request.Method == http.MethodHead {
			c.Next()
			return
		}

		// Skip already-compressed responses (e.g., firmware downloads)
		ce := c.GetHeader("Content-Encoding")
		if ce != "" && ce != "identity" {
			c.Next()
			return
		}

		// Acquire a gzip writer from the pool
		gz := gzipWriterPool.Get().(*gzip.Writer)
		gz.Reset(c.Writer)

		gzWriter := &gzipWriter{
			ResponseWriter: c.Writer,
			writer:         gz,
		}
		c.Writer = gzWriter

		c.Next()

		// Close the gzip writer to flush remaining compressed data
		if gzWriter.gzActive {
			gz.Close()
		}
		gzipWriterPool.Put(gz)
	}
}
