package models

import (
	domain "github.com/domabas/domabas/backend/internal/domain/document/models"
)

func (request DocumentCreateRequest) DomainInput() (domain.DocumentCreateInput, error) {
	if request.Title == nil {
		return domain.DocumentCreateInput{}, domain.DocumentValidationError{Message: "request body is required"}
	}
	input := domain.DocumentCreateInput{Title: *request.Title}
	if request.Description != nil {
		input.Description = *request.Description
	}
	return input, input.Validate()
}

func (request DocumentListRequest) DomainPage() (domain.DocumentPageRequest, error) {
	page := domain.DocumentPageRequest{Limit: 50}
	if request.Limit != nil {
		page.Limit = *request.Limit
	}
	if request.Offset != nil {
		page.Offset = *request.Offset
	}
	if request.Cursor != nil {
		if *request.Cursor == "" {
			return page, domain.DocumentValidationError{Message: "cursor must not be empty"}
		}
		page.Cursor = *request.Cursor
	}
	return page, page.Validate()
}
