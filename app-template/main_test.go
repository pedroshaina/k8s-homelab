package main

import (
	"net/http/httptest"
	"testing"
)

func TestRoutes(t *testing.T) {
	h := handler()
	for _, tc := range []struct {
		method, path string
		want         int
	}{
		{"GET", "/health", 200},
		{"GET", "/ready", 200},
		{"GET", "/", 200},
		{"GET", "/nope", 404},
		{"POST", "/health", 405},
	} {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(tc.method, tc.path, nil))
		if rec.Code != tc.want {
			t.Errorf("%s %s = %d, want %d", tc.method, tc.path, rec.Code, tc.want)
		}
	}
}
