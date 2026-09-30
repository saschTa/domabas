package main

import "testing"

func TestListenAddress(t *testing.T) {
	for _, value := range []string{"", ":9000", "0.0.0.0:8091", "localhost:8091", "[::1]:8091"} {
		actual, err := listenAddress(value)
		expected := value
		if expected == "" {
			expected = ":8091"
		}
		if err != nil || actual != expected {
			t.Fatalf("address %q: got %q, %v", value, actual, err)
		}
	}
	for _, value := range []string{"localhost", "http://localhost:8091", "localhost:0", "localhost:65536", "localhost:http", "bad host:8091", "::1:8091", ":-1"} {
		if _, err := listenAddress(value); err == nil {
			t.Errorf("accepted invalid address %q", value)
		}
	}
}

func TestOllamaQueueCapacity(t *testing.T) {
	for _, scenario := range []struct {
		value string
		want  int
	}{{"", 128}, {"1", 1}, {"3", 3}, {"128", 128}, {"512", 512}} {
		actual, err := ollamaQueueCapacity(scenario.value)
		if err != nil || actual != scenario.want {
			t.Errorf("capacity %q: got %d, %v; want %d", scenario.value, actual, err, scenario.want)
		}
	}
	for _, value := range []string{"0", "-1", "auto", "1.5", "128 ", "99999999999999999999999999"} {
		if _, err := ollamaQueueCapacity(value); err == nil {
			t.Errorf("accepted invalid queue capacity %q", value)
		}
	}
}
