//go:build integration

package repos_test

func searchTotalMatches(mode string, total *int64, expected int64) bool {
	if mode != "fulltext" {
		return total == nil
	}
	return total != nil && *total == expected
}
