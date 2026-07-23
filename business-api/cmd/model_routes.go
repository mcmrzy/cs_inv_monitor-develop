package main

import (
	"inv-api-server/internal/handler"
	"inv-api-server/internal/middleware"

	"github.com/gin-gonic/gin"
)

// registerModelRoutes keeps the legacy model editor and the v2 registry
// workspace on the same authenticated API group. Keeping these routes in one
// place prevents the frontend contract from silently drifting out of main.go.
func registerModelRoutes(auth gin.IRoutes, h *handler.ModelHandler, checker middleware.PermissionChecker) {
	modelsView := middleware.RequirePermission(checker, "models", "view")
	modelsCreate := middleware.RequirePermission(checker, "models", "create")
	modelsEdit := middleware.RequirePermission(checker, "models", "edit")
	modelsDelete := middleware.RequirePermission(checker, "models", "delete")
	dictionaryEdit := middleware.RequirePermission(checker, "models", "dictionary")
	protocolView := middleware.RequirePermission(checker, "models", "protocol_view")
	protocolPublish := middleware.RequirePermission(checker, "models", "protocol_publish")

	// Model CRUD and legacy field/protocol endpoints.
	// The model/field reference reads remain available to every authenticated
	// user because both the mobile app and device detail pages need them to
	// render telemetry. Governance reads and every mutation are RBAC protected.
	auth.GET("/models", h.ListModels)
	auth.POST("/models", modelsCreate, h.CreateModel)
	auth.GET("/models/:id", h.GetModel)
	auth.PUT("/models/:id", modelsEdit, h.UpdateModel)
	auth.DELETE("/models/:id", modelsDelete, h.DeleteModel)
	auth.GET("/models/:id/fields", h.GetModelFields)
	auth.GET("/models/fields-by-code/:code", h.GetFieldsByModelCode)
	auth.POST("/models/:id/fields", modelsEdit, h.CreateField)
	auth.PUT("/models/:id/fields/:fieldId", modelsEdit, h.UpdateField)
	auth.DELETE("/models/:id/fields/:fieldId", modelsEdit, h.DeleteField)
	auth.PUT("/models/:id/fields-batch", modelsEdit, h.BatchUpdateFields)
	auth.GET("/models/:id/protocols", protocolView, h.GetProtocols)
	auth.POST("/models/:id/protocols", protocolPublish, h.CreateProtocol)
	auth.PUT("/models/:id/protocols/:protocolId", protocolPublish, h.UpdateProtocol)
	auth.DELETE("/models/:id/protocols/:protocolId", protocolPublish, h.DeleteProtocol)

	// V2 model registry endpoints used by ModelRegistryWorkspace.
	auth.GET("/field-catalog", modelsView, h.ListFieldCatalog)
	auth.POST("/field-catalog", dictionaryEdit, h.UpsertFieldCatalog)
	auth.GET("/models/:id/field-capabilities", modelsView, h.GetFieldCapabilities)
	auth.PUT("/models/:id/field-capabilities", modelsEdit, h.BatchUpdateFieldCapabilities)
	auth.PUT("/models/:id/field-capabilities/:fieldKey", modelsEdit, h.UpdateFieldCapability)
	auth.GET("/models/:id/commands-v2", modelsView, h.GetModelCommandsV2)
	auth.POST("/models/:id/commands-v2", modelsEdit, h.UpsertModelCommand)
	auth.PUT("/models/:id/commands-v2/:commandCode", modelsEdit, h.UpdateCommandCapability)
	auth.GET("/models/:id/protocol-schema", protocolView, h.GetProtocolSchema)
	auth.GET("/protocol-versions", protocolView, h.ListProtocolVersions)
	auth.POST("/protocol-versions", protocolPublish, h.CreateProtocolVersion)
	auth.POST("/protocol-versions/:protocolId/release", protocolPublish, h.ReleaseProtocolVersion)
	auth.PUT("/models/:id/protocol-version", modelsEdit, h.BindProtocolVersion)
	auth.GET("/models/:id/migration-report", modelsView, h.GetMigrationReport)
	auth.GET("/models/:id/data-preview", modelsView, h.GetDataPreview)
	auth.POST("/models/:id/validate", modelsEdit, h.ValidateRegistry)
	auth.POST("/models/:id/activate", modelsEdit, h.ActivateRegistry)
}
