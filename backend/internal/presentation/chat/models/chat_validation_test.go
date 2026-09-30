package models

import "testing"

func TestChatRequestsRejectAmbiguousObjects(t *testing.T) {
	for _, test := range []struct{ operation, body string }{
		{"create", `null`}, {"create", `{}`}, {"create", `{"requestId":null}`}, {"create", `{"requestId":"x","requestId":"y"}`}, {"create", `{"requestId":"x","ownerId":"y"}`},
		{"send", `{"requestId":"x","content":false}`}, {"send", `{"requestId":"x","content":"hello"} {}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":null,"baseUrl":""}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","apiKey":null,"apiKey":"secret"}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","hasApiKey":true}`},
		{"settings", `{"expectedRevision":1.5,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":""}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","contextLength":null}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","contextLength":32768.5}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","contextLength":32768,"contextLength":65536}`},
	} {
		if ValidateChatObject([]byte(test.body), test.operation) == nil {
			t.Errorf("accepted %s", test.body)
		}
	}
	for _, test := range []struct{ operation, body string }{
		{"create", `{"requestId":"id"}`}, {"send", `{"requestId":"id","content":"Hello 世界"}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"openai","model":"fixture","baseUrl":"http://localhost/v1","apiKey":"secret"}`},
		{"settings", `{"expectedRevision":1,"enabled":false,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","clearApiKey":true}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"openai","model":"fixture","baseUrl":"http://localhost/v1","apiKey":null,"clearApiKey":null}`},
		{"settings", `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"qwen3.5:4b","baseUrl":"","contextLength":32768}`},
	} {
		if err := ValidateChatObject([]byte(test.body), test.operation); err != nil {
			t.Errorf("rejected %s: %v", test.body, err)
		}
	}
}

func TestChatThinkingRequiresUnambiguousBoolean(t *testing.T) {
	for _, value := range []string{"true", "false", "null", `"true"`, "1", `true,"thinkingEnabled":false`} {
		body := `{"expectedRevision":1,"enabled":true,"provider":"ollama","model":"fixture","baseUrl":"","thinkingEnabled":` + value + `}`
		err := ValidateChatObject([]byte(body), "settings")
		if (err == nil) != (value == "true" || value == "false") {
			t.Fatalf("invalid thinking validation %s: %v", body, err)
		}
	}
}
