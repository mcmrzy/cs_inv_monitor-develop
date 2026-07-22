package middleware

import (
	"context"

	"inv-api-server/internal/model"
	"inv-api-server/pkg/jwt"
)

// AuthorizationContextValidator compares token versions and organization
// status with the current database state. Implementations must fail closed.
type AuthorizationContextValidator interface {
	ValidateAuthorizationSessionContext(context.Context, model.AuthorizationSessionContext) (bool, error)
}

func sessionContextFromClaims(claims *jwt.AccessClaims) model.AuthorizationSessionContext {
	return model.AuthorizationSessionContext{
		Actor: model.ActorContext{
			UserID: claims.UserID, RootTenantID: claims.RootTenantID,
			OrganizationID: claims.OrganizationID, MembershipID: claims.MembershipID,
			MembershipVersion: claims.MembershipVersion,
		},
		AuthorizationVersion: claims.AuthorizationVersion,
		SessionVersion:       claims.SessionVersion,
	}
}
