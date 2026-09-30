package provider

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"time"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
)

func (p *ChatProviderRemoteDataSource) ModelContext(ctx context.Context, model string) (m.ChatModelContext, error) {
	if !m.ChatValidModel(model) {
		return m.ChatModelContext{}, m.ChatValidationError{Message: "invalid chat model"}
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return p.modelContext(ctx, model)
}

func (p *ChatProviderRemoteDataSource) modelContext(ctx context.Context, model string) (m.ChatModelContext, error) {
	info, err := p.modelInformation(ctx, model)
	return m.ChatModelContext{Model: model, MaxContextLength: info.MaxContextLength}, err
}

type chatOllamaModelInfo struct {
	ModelInfo        json.RawMessage `json:"model_info"`
	MaxContextLength int             `json:"-"`
}

func (p *ChatProviderRemoteDataSource) modelInformation(ctx context.Context, model string) (chatOllamaModelInfo, error) {
	var response chatOllamaModelInfo
	if err := p.request(ctx, http.MethodPost, p.ollama+"/api/show", "", map[string]string{"model": model}, &response, chatProviderResponseLimit); err != nil {
		return response, err
	}
	var info map[string]json.RawMessage
	var architecture string
	var maximum float64
	if json.Unmarshal(response.ModelInfo, &info) != nil || json.Unmarshal(info["general.architecture"], &architecture) != nil || architecture == "" || json.Unmarshal(info[architecture+".context_length"], &maximum) != nil || maximum <= 0 || maximum > math.MaxInt32 || math.Trunc(maximum) != maximum {
		return response, m.ChatProcessingError{Code: "configuration_unavailable"}
	}
	response.MaxContextLength = int(maximum)
	return response, nil
}
