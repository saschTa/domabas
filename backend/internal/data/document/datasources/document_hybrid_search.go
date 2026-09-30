package datasources

import (
	"fmt"
	m "github.com/domabas/domabas/backend/internal/domain/document/models"
	"strings"
)

func documentHybridSearch(indexed bool) string {
	query := `WITH ` + documentSemanticScores(indexed) + ` terms AS(
 SELECT plainto_tsquery('simple',$10) AS query,tsvector_to_array(to_tsvector('simple',$10)) AS words),
 eligible AS MATERIALIZED(SELECT d.* FROM documents d WHERE ` + searchMetadataEligibility + `),
 metadata_scores AS MATERIALIZED(SELECT d.id,
 CASE WHEN d.metadata_vector @@ terms.query THEN 1+ts_rank_cd(d.metadata_vector,terms.query,32)::float8
 ELSE document_fuzzy_score(terms.words,d.metadata_vector) END AS score
 FROM eligible d CROSS JOIN terms),
 content_scores AS MATERIALIZED(SELECT c.document_id,c.position,left(c.content,512) AS snippet,
 CASE WHEN (d.metadata_vector || c.content_vector) @@ terms.query
 THEN 1+ts_rank_cd(c.content_vector,terms.query,32)::float8
 ELSE document_fuzzy_score(terms.words,d.metadata_vector || c.content_vector) END AS score
 FROM document_chunks c
 JOIN document_processing p ON p.account_id=c.account_id AND p.document_id=c.document_id AND p.generation=c.generation
 JOIN eligible d ON d.account_id=c.account_id AND d.id=c.document_id CROSS JOIN terms),
 content_best AS(SELECT DISTINCT ON(document_id) document_id,score,snippet
 FROM content_scores WHERE score>={fuzzy} ORDER BY document_id,score DESC,position),
 semantic_best AS(SELECT DISTINCT ON(document_id) document_id,score,snippet
 FROM semantic_scores WHERE score>={semantic} ORDER BY document_id,score DESC,position),
 ranked AS(SELECT ` + rankedDocumentColumns + `,
 CASE WHEN m.score>={fuzzy} THEN {metadataPriority}+m.score
 WHEN h.document_id IS NOT NULL THEN {contentPriority}+h.score
 ELSE LEAST({semanticMaximum}::float8,b.score) END AS score,
 CASE WHEN m.score>={fuzzy} THEN left(concat_ws(' ',d.title,d.description,d.subject,d.sender),512)
 ELSE COALESCE(h.snippet,b.snippet) END AS snippet
 FROM eligible d JOIN metadata_scores m ON m.id=d.id CROSS JOIN terms
 LEFT JOIN content_best h ON h.document_id=d.id LEFT JOIN semantic_best b ON b.document_id=d.id
 LEFT JOIN document_processing p ON p.document_id=d.id AND p.account_id=d.account_id
 WHERE cardinality(terms.words)>0 AND (m.score>={fuzzy} OR h.document_id IS NOT NULL OR b.document_id IS NOT NULL)) `
	return strings.NewReplacer("{fuzzy}", fmt.Sprint(m.DocumentFuzzyScoreMinimum), "{semantic}", fmt.Sprint(m.DocumentSemanticScoreMinimum), "{metadataPriority}", fmt.Sprint(m.DocumentMetadataScorePriority), "{contentPriority}", fmt.Sprint(m.DocumentContentScorePriority), "{semanticMaximum}", fmt.Sprint(m.DocumentSemanticScoreMaximum)).Replace(query)
}
