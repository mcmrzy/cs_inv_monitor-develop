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
		log.Fatalf("[Proxy] 无法解析后端地址 %s: %v", target, err)
	}

	proxy := &httputil.ReverseProxy{
		FlushInterval: -1, // 立即刷新，SSE 流式数据不缓冲
		Director: func(req *http.Request) {
			req.URL.Scheme = targetURL.Scheme
			req.URL.Host = targetURL.Host
			req.Host = targetURL.Host
			req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
			if len(req.URL.Path) > 1 && strings.HasSuffix(req.URL.Path, "/") {
				req.URL.Path = strings.TrimSuffix(req.URL.Path, "/")
			}
		},
		Transport: &http.Transport{
			MaxIdleConns:        200,
			MaxIdleConnsPerHost: 50,
			MaxConnsPerHost:     100,
			IdleConnTimeout:     90 * time.Second,
			TLSHandshakeTimeout: 10 * time.Second,
			DialContext: (&net.Dialer{
				Timeout:   10 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
		},
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Printf("[Proxy] 后端服务不可达: %s -> %v", target, err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadGateway)
			fmt.Fprintf(w, `{"code":502,"message":"后端服务不可达","detail":"%s"}`, target)
		},
	}

	return &ReverseProxy{
		targetURL: targetURL,
		proxy:     proxy,
	}
}

func (rp *ReverseProxy) Handler() gin.HandlerFunc {
	return func(c *gin.Context) {
		log.Printf("[DEBUG-INSTRUMENT] ProxyHandler: %s %s -> %s", c.Request.Method, c.Request.URL.Path, rp.targetURL.String())
		rp.proxy.ServeHTTP(c.Writer, c.Request)
		c.Abort()
	}
}

func (rp *ReverseProxy) RewriteHandler(targetPath string) gin.HandlerFunc {
	rewriteProxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			req.URL.Scheme = rp.targetURL.Scheme
			req.URL.Host = rp.targetURL.Host
			req.Host = rp.targetURL.Host
			req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
			originalPath := req.URL.Path
			parts := strings.SplitN(originalPath, "/api/v1/", 2)
			if len(parts) == 2 {
				suffix := parts[1]
				dotIdx := strings.Index(suffix, "/")
				if dotIdx >= 0 {
					suffix = suffix[dotIdx:]
				} else {
					suffix = ""
				}
				req.URL.Path = targetPath + suffix
			}
			if len(req.URL.Path) > 1 && strings.HasSuffix(req.URL.Path, "/") {
				req.URL.Path = strings.TrimSuffix(req.URL.Path, "/")
			}
			log.Printf("[DEBUG-INSTRUMENT] RewriteHandler: %s -> %s", originalPath, req.URL.Path)
		},
		Transport: rp.proxy.Transport,
		ErrorHandler: rp.proxy.ErrorHandler,
	}
	return func(c *gin.Context) {
		rewriteProxy.ServeHTTP(c.Writer, c.Request)
		c.Abort()
	}
}

func (rp *ReverseProxy) Target() string {
	return rp.targetURL.String()
}
