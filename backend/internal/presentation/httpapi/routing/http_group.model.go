package routing

import "time"

type HTTPRouteGroup struct {
	Prefix     string
	Middleware []HTTPMiddleware
	Children   []HTTPRouteGroup
	Timeout    time.Duration
	Streaming  bool
}

type httpRouteScope struct {
	prefix     string
	middleware []HTTPMiddleware
	timeout    time.Duration
	streaming  bool
}
