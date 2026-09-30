package datasources

import (
	"context"
	"fmt"

	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
)

func chatToolResults(ctx context.Context, tx pgx.Tx, turn string) ([]m.ChatToolResult, error) {
	rows, err := tx.Query(ctx, "SELECT kind,query,COALESCE(document_id::text,''),text_offset,tool_call_id,result_text,outcome_code,next_offset FROM chat_tool_results WHERE turn_id=$1 ORDER BY ordinal", turn)
	if err != nil {
		return nil, err
	}
	result := []m.ChatToolResult{}
	for rows.Next() {
		var tool m.ChatToolResult
		if err := rows.Scan(&tool.Action.Kind, &tool.Action.Query, &tool.Action.DocumentID, &tool.Action.Offset, &tool.Action.ToolCallID, &tool.Content, &tool.Outcome, &tool.NextOffset); err != nil {
			rows.Close()
			return nil, err
		}
		result = append(result, tool)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows, err = tx.Query(ctx, "SELECT ordinal,document_id,title,excerpt FROM chat_sources WHERE turn_id=$1 ORDER BY ordinal,document_id", turn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var ordinal int
		var source m.ChatSource
		if err := rows.Scan(&ordinal, &source.DocumentID, &source.Title, &source.Excerpt); err != nil {
			return nil, err
		}
		if ordinal < 0 || ordinal >= len(result) {
			return nil, fmt.Errorf("chat source ordinal %d has no tool result", ordinal)
		}
		result[ordinal].Sources = append(result[ordinal].Sources, source)
	}
	return result, rows.Err()
}
