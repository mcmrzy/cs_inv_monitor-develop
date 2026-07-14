package main

import (
	"inv-api-server/internal/handler"

	"github.com/gin-gonic/gin"
)

// registerModelRoutes keeps the legacy model editor and the v2 registry
// workspace on the same authenticated API group. Keeping these routes in one
// place prevents the frontend contract from silently drifting out of main.go.
func registerModelRoutes(auth gin.IRoutes, h *handler.ModelHandler) {
	// Model CRUD and legacy field/protocol endpoints.
	auth.GET("/models", h.ListModels)
	auth.POST("/models", h.CreateModel)
	auth.GET("/models/:id", h.GetModel)
	auth.PUT("/models/:id", h.UpdateModel)
	auth.DELETE("/models/:id", h.DeleteModel)
	auth.GET("/models/:id/fields", h.GetModelFields)
	auth.GET("/models/by-code/:code/fields", h.GetFieldsByModelCode)
	auth.POST("/models/:id/fields", h.CreateField)
	auth.PUT("/models/:id/fields/:fieldId", h.UpdateField)
	auth.DELETE("/models/:id/fields/:fieldId", h.DeleteField)
	auth.PUT("/models/:id/fields/batch", h.BatchUpdateFields)
	auth.GET("/models/:id/protocols", h.GetProtocols)
	auth.POST("/models/:id/protocols", h.CreateProtocol)
	auth.PUT("/models/:id/protocols/:protocolId", h.UpdateProtocol)
	auth.DELETE("/models/:id/protocols/:protocolId", h.DeleteProtocol)

	// V2 model registry endpoints used by ModelRegistryWorkspace.
	auth.GET("/field-catalog", h.ListFieldCatalog)
	auth.POST("/field-catalog", h.UpsertFieldCatalog)
	auth.GET("/models/:id/field-capabilities", h.GetFieldCapabilities)
	auth.PUT("/models/:id/field-capabilities", h.BatchUpdateFieldCapabilities)
	auth.PUT("/models/:id/field-capabilities/:fieldKey", h.UpdateFieldCapability)
	auth.GET("/models/:id/commands-v2", h.GetModelCommandsV2)
	auth.POST("/models/:id/commands-v2", h.UpsertModelCommand)
	auth.PUT("/models/:id/commands-v2/:commandCode", h.UpdateCommandCapability)
	auth.GET("/models/:id/protocol-schema", h.GetProtocolSchema)
	auth.GET("/protocol-versions", h.ListProtocolVersions)
	auth.POST("/protocol-versions", h.CreateProtocolVersion)
	auth.POST("/protocol-versions/:protocolId/release", h.ReleaseProtocolVersion)
	auth.PUT("/models/:id/protocol-version", h.BindProtocolVersion)
	auth.GET("/models/:id/migration-report", h.GetMigrationReport)
	auth.GET("/models/:id/data-preview", h.GetDataPreview)
	auth.POST("/models/:id/validate", h.ValidateRegistry)
	auth.POST("/models/:id/activate", h.ActivateRegistry)
}
