//go:build e2e

package e2e_test

import "time"

func (api *ingestionAPI) waitAI(token, id, status string) map[string]any {
	api.t.Helper()
	deadline := time.Now().Add(3 * time.Minute)
	var processing map[string]any
	for time.Now().Before(deadline) {
		processing = api.request(token, "GET", "/api/v1/documents/"+id+"/processing", "", 200, "DocumentProcessing")
		if processing["state"] != "ready" {
			api.t.Fatalf("AI processing changed searchable ingestion: %v", processing)
		}
		if ai, ok := processing["ai"].(map[string]any); ok {
			if ai["status"] == status {
				return ai
			}
			if ai["status"] == "failed" || ai["status"] == "cancelled" || ai["status"] == "superseded" {
				api.t.Fatalf("AI processing stopped before %s: %v", status, ai)
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	api.t.Fatalf("AI processing did not reach %s: %v", status, processing)
	return nil
}
