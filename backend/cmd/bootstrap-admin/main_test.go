package main

import "testing"

func TestBootstrapRequiresExplicitUserBeforeDatabaseAccess(t *testing.T) {
	for _, args := range [][]string{nil, {"--user-id", "invalid"}, {"--user-id", "00000000-0000-0000-0000-000000000000"}, {"--other"}, {"--user-id", "31c83373-8351-4b8e-9a3f-fb2a9097e099", "extra"}} {
		if err := run(args); err == nil {
			t.Fatalf("accepted invalid arguments %v", args)
		}
	}
}
