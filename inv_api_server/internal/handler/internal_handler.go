package handler

import (
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

func InternalDeviceStatus(c *gin.Context) {
	response.Success(c, gin.H{"message": "ok"})
}

func InternalDeviceInfo(c *gin.Context) {
	response.Success(c, gin.H{"message": "ok"})
}

func InternalDeviceData(c *gin.Context) {
	response.Success(c, gin.H{"message": "ok"})
}

func InternalDeviceCmdStatus(c *gin.Context) {
	response.Success(c, gin.H{"message": "ok"})
}
