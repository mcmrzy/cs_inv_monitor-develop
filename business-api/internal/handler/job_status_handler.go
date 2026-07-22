package handler

import (
	"fmt"
	"net/http"
	"time"

	"inv-api-server/internal/job"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// JobStatusHandler handles job status and progress queries
type JobStatusHandler struct {
	jobStore *job.JobStore
}

// NewJobStatusHandler creates a new job status handler
func NewJobStatusHandler(jobStore *job.JobStore) *JobStatusHandler {
	return &JobStatusHandler{jobStore: jobStore}
}

// GetJobStatus handles GET /api/v1/jobs/:jobId/status - Get job status and progress
func (h *JobStatusHandler) GetJobStatus(c *gin.Context) {
	jobID := c.Param("jobId")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id required"})
		return
	}

	ctx := c.Request.Context()
	job, err := h.jobStore.GetJob(ctx, jobID)
	if err != nil {
		response.HandleError(c, apperr.NotFound("作业不存在或已过期"))
		return
	}

	// Get current progress from Redis hash
	processed, total, status, _ := h.jobStore.GetProgress(ctx, jobID)

	response.Success(c, map[string]interface{}{
		"job_id":        job.JobID,
		"job_type":      job.Type,
		"status":        job.Status,
		"total":         total,
		"processed":     processed,
		"progress":      job.Progress,
		"retry_count":   job.RetryCount,
		"error_message": job.ErrorMessage,
		"created_at":    job.CreatedAt.Unix(),
		"updated_at":    job.UpdatedAt.Unix(),
		"completed_at":  job.CompletedAt,
	})
}

// GetJobStats handles GET /api/v1/jobs/stats - Get overall job statistics
func (h *JobStatusHandler) GetJobStats(c *gin.Context) {
	ctx := c.Request.Context()
	stats, err := h.jobStore.GetStats(ctx)
	if err != nil {
		response.HandleError(c, apperr.Internal("获取作业统计失败", err))
		return
	}

	response.Success(c, stats)
}

// ListJobs handles GET /api/v1/jobs/list - List jobs by status
func (h *JobStatusHandler) ListJobs(c *gin.Context) {
	ctx := c.Request.Context()
	status := c.DefaultQuery("status", "pending")

	var jobIDs []string
	var err error

	switch status {
	case "pending":
		jobIDs, err = h.jobStore.GetPendingJobs(ctx)
	case "running":
		jobIDs, err = h.jobStore.GetRunningJobs(ctx)
	case "completed":
		jobIDs, err = h.jobStore.GetCompletedJobs(ctx, 100)
	case "failed":
		jobIDs, err = h.jobStore.GetFailedJobs(ctx, 100)
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status parameter"})
		return
	}

	if err != nil {
		response.HandleError(c, apperr.Internal("获取作业列表失败", err))
		return
	}

	// Fetch detailed job information for each ID
	jobs := make([]map[string]interface{}, 0, len(jobIDs))
	for _, id := range jobIDs {
		job, err := h.jobStore.GetJob(ctx, id)
		if err != nil {
			continue
		}

		jobs = append(jobs, map[string]interface{}{
			"job_id":        job.JobID,
			"job_type":      job.Type,
			"status":        job.Status,
			"total":         job.TotalItems,
			"progress":      job.Progress,
			"created_at":    job.CreatedAt.Unix(),
			"updated_at":    job.UpdatedAt.Unix(),
			"completed_at":  job.CompletedAt,
			"error_message": job.ErrorMessage,
		})
	}

	response.Success(c, gin.H{
		"status": status,
		"count":  len(jobs),
		"jobs":   jobs,
	})
}

// CancelJob handles POST /api/v1/jobs/:jobId/cancel - Cancel a pending job
func (h *JobStatusHandler) CancelJob(c *gin.Context) {
	jobID := c.Param("jobId")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id required"})
		return
	}

	ctx := c.Request.Context()
	job, err := h.jobStore.GetJob(ctx, jobID)
	if err != nil {
		response.HandleError(c, apperr.NotFound("作业不存在"))
		return
	}

	// Only pending jobs can be cancelled
	if job.Status != "pending" {
		response.HandleError(c, apperr.Conflict("只有等待中的作业可以被取消"))
		return
	}

	// Update job status to cancelled
	job.Status = "cancelled"
	if err := h.jobStore.UpdateStatus(job); err != nil {
		response.HandleError(c, apperr.Internal("取消作业失败", err))
		return
	}

	response.SuccessWithMessage(c, "作业已取消", gin.H{
		"job_id": jobID,
		"status": "cancelled",
	})
}

// DeleteJob handles DELETE /api/v1/jobs/:jobId - Delete a job record
func (h *JobStatusHandler) DeleteJob(c *gin.Context) {
	jobID := c.Param("jobId")
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id required"})
		return
	}

	ctx := c.Request.Context()

	// Verify job exists
	_, err := h.jobStore.GetJob(ctx, jobID)
	if err != nil {
		response.HandleError(c, apperr.NotFound("作业不存在"))
		return
	}

	// Delete job and progress data
	if err := h.jobStore.DeleteJob(ctx, jobID); err != nil {
		response.HandleError(c, apperr.Internal("删除作业失败", err))
		return
	}

	response.SuccessWithMessage(c, "作业已删除", gin.H{
		"job_id": jobID,
	})
}

// CleanupOldJobs handles POST /api/v1/jobs/cleanup - Remove old job records
func (h *JobStatusHandler) CleanupOldJobs(c *gin.Context) {
	var req struct {
		Hours int `json:"hours" binding:"required,min=1,max=168"` // 1 hour to 1 week
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request: hours required (1-168)"})
		return
	}

	ctx := c.Request.Context()
	olderThan := time.Duration(req.Hours) * time.Hour

	count, err := h.jobStore.CleanupOldJobs(ctx, olderThan)
	if err != nil {
		response.HandleError(c, apperr.Internal("清理作业失败", err))
		return
	}

	response.SuccessWithMessage(c, "旧作业已清理", gin.H{
		"jobs_removed": count,
		"older_than":   fmt.Sprintf("%d hours", req.Hours),
	})
}
