package proxy

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type ReverseProxy struct {
	targetURL *url.URL
	proxy     *httputil.ReverseProxy
}

func NewReverseProxy(target string) *ReverseProxy {
	targetURL, err := url.Parse(target)
	if err != nil {
		log.Fatalf("[Proxy] invalid backend URL: %v", err)
	}
	proxy := &httputil.ReverseProxy{
		FlushInterval: -1,
		Director: func(req *http.Request) {
			req.URL.Scheme, req.URL.Host, req.Host = targetURL.Scheme, targetURL.Host, targetURL.Host
			req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
			if len(req.URL.Path) > 1 && strings.HasSuffix(req.URL.Path, "/") {
				req.URL.Path = strings.TrimSuffix(req.URL.Path, "/")
			}
		},
		Transport: &http.Transport{
			MaxIdleConns: 200, MaxIdleConnsPerHost: 50, MaxConnsPerHost: 100,
			IdleConnTimeout: 90 * time.Second, TLSHandshakeTimeout: 10 * time.Second,
			DialContext: (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("[Proxy] backend unavailable for %s %s: %v", r.Method, r.URL.Path, err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadGateway)
			_, _ = fmt.Fprint(w, `{"code":502,"message":"后端服务不可达"}`)
		},
	}
	return &ReverseProxy{targetURL: targetURL, proxy: proxy}
}

func (rp *ReverseProxy) Handler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Request.Header.Set("X-Forwarded-For", c.ClientIP())
		rp.proxy.ServeHTTP(c.Writer, c.Request)
		c.Abort()
	}
}

func (rp *ReverseProxy) RewriteHandler(targetPath string) gin.HandlerFunc {
	rewriteProxy := &httputil.ReverseProxy{
		FlushInterval: -1,
		Director: func(req *http.Request) {
			req.URL.Scheme, req.URL.Host, req.Host = rp.targetURL.Scheme, rp.targetURL.Host, rp.targetURL.Host
			req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
			parts := strings.SplitN(req.URL.Path, "/api/v1/", 2)
			if len(parts) == 2 {
				suffix := parts[1]
				if dotIdx := strings.Index(suffix, "/"); dotIdx >= 0 {
					suffix = suffix[dotIdx:]
				} else {
					suffix = ""
				}
				req.URL.Path = targetPath + suffix
			}
			if len(req.URL.Path) > 1 && strings.HasSuffix(req.URL.Path, "/") {
				req.URL.Path = strings.TrimSuffix(req.URL.Path, "/")
			}
		},
		Transport: rp.proxy.Transport, ErrorHandler: rp.proxy.ErrorHandler,
	}
	return func(c *gin.Context) {
		c.Request.Header.Set("X-Forwarded-For", c.ClientIP())
		rewriteProxy.ServeHTTP(c.Writer, c.Request)
		c.Abort()
	}
}

func (rp *ReverseProxy) Target() string { return rp.targetURL.String() }
