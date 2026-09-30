package datasources

import (
	"context"
	"encoding/json"
	"errors"
	data "github.com/domabas/domabas/backend/internal/data/chat/models"
	m "github.com/domabas/domabas/backend/internal/domain/chat/models"
	"github.com/jackc/pgx/v5"
)

type ChatToolDocument struct {
	DocumentID string `json:"documentId"`
	Title      string `json:"title"`
	Excerpt    string `json:"excerpt,omitempty"`
	Text       string `json:"text,omitempty"`
	NextOffset *int   `json:"nextOffset,omitempty"`
}
type ChatToolSearchPage struct {
	Items      []ChatToolDocument `json:"items"`
	NextOffset *int               `json:"nextOffset,omitempty"`
	Guidance   string             `json:"guidance,omitempty"`
}

func (s *ChatDataSource) ToolFacts(ctx context.Context, id, token string) ([]m.ChatToolResult, error) {
	var result []m.ChatToolResult
	err := s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		var err error
		result, err = chatToolResults(ctx, tx, id)
		return err
	})
	return result, err
}

func (s *ChatDataSource) ToolEvidence(ctx context.Context, id, token string, action m.ChatAction) (m.ChatToolEvidence, error) {
	result := m.ChatToolEvidence{Available: true, Sources: []m.ChatSource{}}
	err := s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		if action.Kind == "list_tools" {
			page := data.NewChatToolCatalogPage(action.Offset)
			result.NextOffset = page.NextOffset
			if len(page.Items) == 0 {
				result.Empty = true
			}
			body, err := json.Marshal(page)
			if err != nil {
				return err
			}
			result.Content = string(body)
		} else if action.Kind == "search_documents" {
			page := ChatToolSearchPage{Items: []ChatToolDocument{}}
			rows, err := tx.Query(ctx, `WITH terms AS (SELECT websearch_to_tsquery('simple',$2) query) SELECT d.id,d.title,COALESCE((SELECT left(c.content,500) FROM document_chunks c JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation WHERE c.account_id=d.account_id AND c.document_id=d.id AND c.content_vector@@terms.query ORDER BY c.position LIMIT 1),left(concat_ws(' ',d.title,d.description,d.subject,d.sender),500)) FROM documents d CROSS JOIN terms WHERE d.account_id=$1 AND (d.metadata_vector@@terms.query OR EXISTS(SELECT 1 FROM document_chunks c JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation WHERE c.account_id=d.account_id AND c.document_id=d.id AND c.content_vector@@terms.query)) ORDER BY d.created_at DESC,d.id DESC LIMIT 11 OFFSET $3`, a.AccountID, action.Query, action.Offset)
			if err != nil {
				return err
			}
			for rows.Next() {
				var d ChatToolDocument
				if err := rows.Scan(&d.DocumentID, &d.Title, &d.Excerpt); err != nil {
					rows.Close()
					return err
				}
				page.Items = append(page.Items, d)
			}
			rows.Close()
			if err := rows.Err(); err != nil {
				return err
			}
			if len(page.Items) > 10 {
				page.Items = page.Items[:10]
				next := action.Offset + 10
				page.NextOffset = &next
			}
			result.NextOffset = page.NextOffset
			for _, d := range page.Items {
				result.Sources = append(result.Sources, m.ChatSource{DocumentID: d.DocumentID, Title: d.Title, Excerpt: d.Excerpt})
			}
			result.Empty = len(page.Items) == 0
			body, err := json.Marshal(page)
			if err != nil {
				return err
			}
			result.Content = string(body)
		} else {
			var d ChatToolDocument
			var remaining int
			err := tx.QueryRow(ctx, `SELECT id,title,substring(COALESCE(ocr_manual_text,ocr_machine_text,'') FROM $3+1 FOR 8000),char_length(COALESCE(ocr_manual_text,ocr_machine_text,'')) FROM documents WHERE account_id=$1 AND id=$2`, a.AccountID, action.DocumentID, action.Offset).Scan(&d.DocumentID, &d.Title, &d.Text, &remaining)
			if errors.Is(err, pgx.ErrNoRows) {
				result.Available = false
			} else if err != nil {
				return err
			} else {
				if action.Offset+8000 < remaining {
					next := action.Offset + 8000
					d.NextOffset = &next
				}
				result.NextOffset = d.NextOffset
				if len(d.Text) == 0 {
					result.Empty = true
				}
				excerpt := []rune(d.Text)
				if len(excerpt) > 500 {
					excerpt = excerpt[:500]
				}
				result.Sources = append(result.Sources, m.ChatSource{DocumentID: d.DocumentID, Title: d.Title, Excerpt: string(excerpt)})
				body, err := json.Marshal(d)
				if err != nil {
					return err
				}
				result.Content = string(body)
			}
		}

		return nil
	})
	return result, err
}

func (s *ChatDataSource) SaveTool(ctx context.Context, id, token string, ordinal int, result m.ChatToolResult) (m.ChatToolResult, error) {
	action := result.Action
	err := s.executionTx(ctx, id, token, func(tx pgx.Tx, a m.ChatActor, conversation string) error {
		prior, err := chatToolResults(ctx, tx, id)
		if err != nil {
			return err
		}
		if ordinal < len(prior) {
			if prior[ordinal].Action != action {
				return m.ErrConflict
			}
			result = prior[ordinal]
			return nil
		}
		if len(prior) != ordinal {
			return m.ErrConflict
		}
		if _, err := tx.Exec(ctx, "INSERT INTO chat_tool_results(turn_id,ordinal,kind,query,document_id,text_offset,tool_call_id,result_text,outcome_code,next_offset) VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid,$6,$7,$8,$9,$10)", id, ordinal, action.Kind, action.Query, action.DocumentID, action.Offset, action.ToolCallID, result.Content, result.Outcome, result.NextOffset); err != nil {
			return err
		}
		for _, source := range result.Sources {
			if _, err := tx.Exec(ctx, "INSERT INTO chat_sources(turn_id,ordinal,document_id,title,excerpt) VALUES($1,$2,$3,$4,$5)", id, ordinal, source.DocumentID, source.Title, source.Excerpt); err != nil {
				return err
			}
		}
		return nil

	})
	return result, err
}
