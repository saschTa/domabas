//go:build e2e

package e2e_test

import (
	"encoding/json"
	"fmt"
	"reflect"
)

func verifyWorkloadSettings(api *ingestionAPI, admin, namespaceOwner string) {
	api.t.Helper()
	path := "/api/v1/system/workload-settings"
	api.request(namespaceOwner, "GET", path, "", 403, "Error")
	api.request(namespaceOwner, "PUT", path, "{", 403, "Error")
	settings := api.request(admin, "GET", path, "", 200, "WorkloadSettings")
	if settings["ollamaQueueSize"] != float64(9) {
		api.t.Fatal("wrong queue ceiling", settings)
	}
	limits := map[string]int{}
	maximum := map[string]int{}
	for _, item := range settings["resources"].([]any) {
		resource := item.(map[string]any)
		limits[resource["id"].(string)] = int(resource["limit"].(float64))
		maximum[resource["id"].(string)] = int(resource["maximumLimit"].(float64))
	}
	if limits["worker"] != 10 || limits["ollama"] != 1 || maximum["ollama"] != 4 {
		api.t.Fatal("unsafe scheduler defaults or half-queue ceiling", settings)
	}
	requirements := map[string][]any{}
	for _, item := range settings["pipelines"].([]any) {
		pipeline := item.(map[string]any)
		requirements[pipeline["id"].(string)] = pipeline["resourceIds"].([]any)
		counts := pipeline["activeSlots"].(map[string]any)
		for _, id := range pipeline["resourceIds"].([]any) {
			if count, ok := counts[id.(string)].(float64); !ok || count < 0 {
				api.t.Fatalf("missing slot count for %s: %v", id, pipeline)
			}
		}
	}
	for pipeline, expected := range map[string][]any{
		"email":              {"worker"},
		"paperless":          {"worker", "stage:paperless"},
		"document_ingestion": {"worker", "stage:thumbnail", "stage:ocr", "stage:embedding", "ollama"},
	} {
		if !reflect.DeepEqual(requirements[pipeline], expected) {
			api.t.Fatalf("unexpected resource requirements for %s: %v", pipeline, requirements[pipeline])
		}
	}
	revision := settings["revision"]
	changed := api.request(admin, "PUT", path, fmt.Sprintf(`{"expectedRevision":%.0f,"resources":[{"id":"worker","limit":11},{"id":"ollama","limit":2}]}`, revision), 200, "WorkloadSettings")
	if changed["revision"].(float64) != revision.(float64)+1 {
		api.t.Fatal("settings revision did not advance", changed)
	}
	api.request(admin, "PUT", path, fmt.Sprintf(`{"expectedRevision":%.0f,"resources":[{"id":"worker","limit":12}]}`, revision), 409, "Error")
	revision = changed["revision"]
	for _, resources := range []string{`[{"id":"ollama","limit":5}]`, `[{"id":"worker","limit":0}]`, `[{"id":"missing","limit":1}]`, `[{"id":"worker","limit":1},{"id":"worker","limit":2}]`} {
		api.request(admin, "PUT", path, fmt.Sprintf(`{"expectedRevision":%.0f,"resources":%s}`, revision, resources), 400, "Error")
	}
	updates := []map[string]any{}
	for id, limit := range limits {
		updates = append(updates, map[string]any{"id": id, "limit": limit})
	}
	encoded, err := json.Marshal(map[string]any{"expectedRevision": revision, "resources": updates})
	if err != nil {
		api.t.Fatal(err)
	}
	restored := api.request(admin, "PUT", path, string(encoded), 200, "WorkloadSettings")
	for _, item := range restored["resources"].([]any) {
		resource := item.(map[string]any)
		if int(resource["limit"].(float64)) != limits[resource["id"].(string)] {
			api.t.Fatal("settings did not restore", restored)
		}
	}
}
