package datasources

import m "github.com/domabas/domabas/backend/internal/domain/chat/models"

func chatMessageMapper(row ChatRowScanner) (m.ChatMessage, error) {
	var v m.ChatMessage
	err := row.Scan(&v.ID, &v.ConversationID, &v.TurnID, &v.Sequence, &v.Role, &v.Content, &v.CreatedAt, &v.UpdatedAt, &v.Status, &v.Stage, &v.FailureCode, &v.Provider, &v.Model)
	v.Sources = []m.ChatSource{}
	return v, err
}
