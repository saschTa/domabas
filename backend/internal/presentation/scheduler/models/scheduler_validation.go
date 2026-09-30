package models

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"unicode/utf8"

	m "github.com/domabas/domabas/backend/internal/domain/scheduler/models"
)

func schedulerObject(body []byte, fields ...string) (map[string]json.RawMessage, error) {
	invalid := errors.New("invalid workload settings object")
	if !utf8.Valid(body) {
		return nil, invalid
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return nil, invalid
	}
	values := make(map[string]json.RawMessage, len(fields))
	for decoder.More() {
		token, err := decoder.Token()
		name, ok := token.(string)
		if err != nil || !ok || values[name] != nil {
			return nil, invalid
		}
		allowed := false
		for _, field := range fields {
			if field == name {
				allowed = true
				break
			}
		}
		if !allowed {
			return nil, invalid
		}
		var value json.RawMessage
		if decoder.Decode(&value) != nil || bytes.Equal(bytes.TrimSpace(value), []byte("null")) {
			return nil, invalid
		}
		values[name] = value
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('}') || decoder.Decode(new(any)) != io.EOF || len(values) != len(fields) {
		return nil, invalid
	}
	return values, nil
}

func ValidateSettings(body []byte) error {
	values, err := schedulerObject(body, "expectedRevision", "resources")
	if err != nil {
		return err
	}
	var update m.SchedulerSettingsUpdate
	if err = json.Unmarshal(values["expectedRevision"], &update.ExpectedRevision); err != nil {
		return err
	}
	var resources []json.RawMessage
	if err = json.Unmarshal(values["resources"], &resources); err != nil {
		return err
	}
	for _, resource := range resources {
		fields, err := schedulerObject(resource, "id", "limit")
		if err != nil {
			return err
		}
		var item m.SchedulerResourceUpdate
		if err = json.Unmarshal(fields["id"], &item.ID); err != nil {
			return err
		}
		if err = json.Unmarshal(fields["limit"], &item.Limit); err != nil {
			return err
		}
		update.Resources = append(update.Resources, item)
	}
	return update.Validate()
}
