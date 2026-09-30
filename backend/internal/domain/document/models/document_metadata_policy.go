package models

func (current DocumentMetadata) FillExtractedProperties(extracted DocumentMetadata) DocumentMetadata {
	if current.Description == "" {
		current.Description = extracted.Description
	}
	if len(current.Tags) == 0 && len(extracted.Tags) > 0 {
		current.Tags = extracted.Tags
	}
	if current.Sender == "" {
		current.Sender = extracted.Sender
	}
	if len(current.Recipients) == 0 && len(extracted.Recipients) > 0 {
		current.Recipients = extracted.Recipients
	}
	if current.DocumentDate == "" {
		current.DocumentDate = extracted.DocumentDate
	}
	if current.Subject == "" {
		current.Subject = extracted.Subject
	}
	return current
}
