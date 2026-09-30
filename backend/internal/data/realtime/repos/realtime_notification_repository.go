package repos

import (
	r "github.com/domabas/domabas/backend/internal/data/realtime/models"
	m "github.com/domabas/domabas/backend/internal/domain/realtime/models"
)

type RealtimeNotificationTarget interface {
	Publish(m.RealtimeSignal)
	SetHealthy(bool)
}
type RealtimeNotificationRepository struct{ target RealtimeNotificationTarget }

func NewRealtimeNotificationRepository(target RealtimeNotificationTarget) *RealtimeNotificationRepository {
	return &RealtimeNotificationRepository{target: target}
}
func (r *RealtimeNotificationRepository) Notify(signal r.RealtimeSignal) {
	r.target.Publish(m.RealtimeSignal{Kind: signal.Kind, AccountID: signal.AccountID, UserID: signal.UserID})
}
func (r *RealtimeNotificationRepository) Health(healthy bool) { r.target.SetHealthy(healthy) }
