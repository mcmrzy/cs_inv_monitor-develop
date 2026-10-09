package handler

import (
	"context"
	"errors"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

var errOverviewDenied = errors.New("overview permission denied")

func loadOverviewScope(ctx context.Context, db *pgxpool.Pool, actor model.ActorContext, adminFlag bool, resourceType string) (model.ScopePlan, bool, error) {
	if !actor.Valid() {
		return model.ScopePlan{}, false, errOverviewDenied
	}
	repo := repository.NewAuthorizationRepository(db)
	permission := resourceType + "s:view"
	if adminFlag && repository.IsSyntheticOverviewActor(actor) && (resourceType == "device" || resourceType == "station") {
		allowed, err := repo.ValidateSyntheticOverviewAdmin(ctx, actor)
		if err != nil {
			return model.ScopePlan{}, false, err
		}
		if allowed {
			return model.ScopePlan{Actor: actor, PermissionCode: permission, ResourceType: resourceType}, true, nil
		}
	}
	plan, err := service.NewAuthorizationService(repo).BuildScope(ctx, actor, permission, resourceType)
	if err != nil {
		return plan, false, err
	}
	// The authenticated flag alone cannot keep privileges after admin revocation.
	systemAdmin := false
	if adminFlag && plan.DenyReason != model.DenyContextInactive {
		err = db.QueryRow(ctx,
			"SELECT is_system_admin FROM users WHERE id=$1 AND status=1 AND deleted_at IS NULL", actor.UserID).Scan(&systemAdmin)
		if err != nil {
			return plan, false, err
		}
	}
	if systemAdmin && plan.DenyReason == model.DenyPermissionNotGranted {
		plan.DenyReason = ""
	}
	if plan.DenyReason != "" {
		return plan, false, errOverviewDenied
	}
	return plan, systemAdmin, nil
}

func overviewScope(c *gin.Context, db *pgxpool.Pool, resourceType string) (model.ScopePlan, bool, bool) {
	actor := middleware.GetActorContext(c)
	if actor.UserID != middleware.GetUserID(c) {
		response.Forbidden(c, "permission denied")
		return model.ScopePlan{}, false, false
	}
	plan, admin, err := loadOverviewScope(c.Request.Context(), db, actor, middleware.GetIsSystemAdmin(c), resourceType)
	if err != nil {
		if errors.Is(err, errOverviewDenied) {
			response.Forbidden(c, "permission denied")
		} else {
			response.InternalError(c, "authorization state unavailable")
		}
		return plan, false, false
	}
	return plan, admin, true
}

func (h *StationHandler) overviewDeviceStats(c *gin.Context, stationPlan model.ScopePlan, systemAdmin bool, stations []*model.Station) (map[int64]repository.StationOverviewDeviceStats, error) {
	devicePlan, deviceAdmin, err := h.overviewDeviceScope(c, stationPlan)
	if err != nil {
		return nil, err
	}
	ids := make([]int64, 0, len(stations))
	for _, station := range stations {
		ids = append(ids, station.ID)
	}
	return h.stationService.OverviewDeviceStats(c.Request.Context(), stationPlan, devicePlan, systemAdmin && deviceAdmin, ids)
}

func (h *StationHandler) overviewDeviceScope(c *gin.Context, stationPlan model.ScopePlan) (model.ScopePlan, bool, error) {
	plan, admin, err := loadOverviewScope(c.Request.Context(), h.db, stationPlan.Actor, middleware.GetIsSystemAdmin(c), "device")
	if errors.Is(err, errOverviewDenied) {
		return plan, false, nil
	}
	return plan, admin, err
}

func (h *StationHandler) overviewStation(c *gin.Context, id int64) (*model.Station, model.ScopePlan, bool, bool) {
	plan, admin, allowed := overviewScope(c, h.db, "station")
	if !allowed {
		return nil, plan, admin, false
	}
	station, err := h.stationService.GetOverviewByID(c.Request.Context(), plan, admin, id)
	if err != nil {
		response.InternalError(c, "get station failed")
		return nil, plan, admin, false
	}
	if station == nil {
		response.Forbidden(c, "permission denied")
		return nil, plan, admin, false
	}
	return station, plan, admin, true
}
