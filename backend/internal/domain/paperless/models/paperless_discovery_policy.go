package models

type PaperlessPageFacts struct {
	Page, Count int
	Total       *int
	Previous    int64
	Cancelled   bool
}

type PaperlessPageCommand struct {
	Expected PaperlessPageFacts
	Page     PaperlessPage
	Stage    string
}

func PlanPaperlessPage(facts PaperlessPageFacts, page int, input PaperlessPage) (*PaperlessPageCommand, error) {
	if facts.Cancelled || facts.Page != page {
		return nil, nil
	}
	if facts.Total != nil && *facts.Total != input.Total {
		return nil, PaperlessFailure{Code: "source_changed"}
	}
	next := facts.Count + len(input.Items)
	if next > input.Total || (len(input.Items) > 0 && input.Items[0].ID <= facts.Previous) || (!input.HasMore && next != input.Total) || (input.HasMore && next == input.Total) {
		return nil, PaperlessFailure{Code: "source_changed"}
	}
	stage := "discovering"
	if !input.HasMore {
		stage = "importing"
	}
	return &PaperlessPageCommand{Expected: facts, Page: input, Stage: stage}, nil
}
