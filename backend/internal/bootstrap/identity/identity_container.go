package identity

import (
	"time"

	identitysources "github.com/domabas/domabas/backend/internal/data/identity/datasources"
	identityrepos "github.com/domabas/domabas/backend/internal/data/identity/repos"
	identitysecurity "github.com/domabas/domabas/backend/internal/data/identity/security"
	"github.com/domabas/domabas/backend/internal/data/postgres"
	identityservices "github.com/domabas/domabas/backend/internal/domain/identity/services"
	"github.com/google/uuid"
)

type IdentityContainer struct {
	service    *identityservices.IdentityService
	activity   *identityservices.IdentityActivityService
	authorizer *identitysecurity.CasbinIdentityAuthorizer
}

func NewIdentityContainer(database *postgres.PostgresDatabase, now func() time.Time) (*IdentityContainer, error) {
	authorizer, err := identitysecurity.NewCasbinIdentityAuthorizer()
	if err != nil {
		return nil, err
	}
	source := identitysources.NewIdentityDataSource(database)
	repository := identityrepos.NewIdentityRepository(source)
	passwords := identitysecurity.NewArgon2IdentityPasswords()
	service := identityservices.NewIdentityService(repository, passwords, authorizer, now, uuid.NewString)
	return &IdentityContainer{service: service, activity: identityservices.NewIdentityActivityService(identityrepos.NewIdentityActivityRepository(source), service, authorizer), authorizer: authorizer}, nil
}
func (c *IdentityContainer) Activity() *identityservices.IdentityActivityService { return c.activity }
func (c *IdentityContainer) Service() *identityservices.IdentityService          { return c.service }
func (c *IdentityContainer) Authorizer() *identitysecurity.CasbinIdentityAuthorizer {
	return c.authorizer
}
