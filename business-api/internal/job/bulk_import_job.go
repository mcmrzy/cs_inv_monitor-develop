package job

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"strings"
	"time"

	"inv-api-server/pkg/logger"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// JobType defines the type of background job
type JobType string

const (
	JobBulkAddMembers    JobType = "bulk_add_members"
	JobBulkTransfer      JobType = "bulk_transfer_members"
	JobBulkExport        JobType = "bulk_export"
	JobBulkImport        JobType = "bulk_import"
)

// JobStatus represents the current status of a job
type JobStatus string

const (
	StatusPending   JobStatus = "pending"
	StatusProcessing JobStatus = "processing"
	StatusCompleted JobStatus = "completed"
	StatusFailed    JobStatus = "failed"
	StatusCancelled JobStatus = "cancelled"
)

// DefaultBatchSize is the chunk size for processing
const DefaultBatchSize = 100

// MaxRetries is the maximum number of retry attempts
const MaxRetries = 3

// MaxJobDuration is the maximum duration a job can run (5 minutes)
const MaxJobDuration = 5 * time.Minute

// BulkItem represents a single item in a bulk operation
type BulkItem struct {
	UserID       int64   `json:"user_id"`
	MembershipID int64   `json:"membership_id,omitempty"`
	RoleIDs      []int   `json:"role_ids,omitempty"`
	ExtraData    map[string]interface{} `json:"extra_data,omitempty"`
}

// BulkImportJob represents a background job for bulk operations
type BulkImportJob struct {
	JobID        string       `json:"job_id"`
	Type         JobType      `json:"job_type"`
	UserID       int64        `json:"user_id"`
	OrganizationID int64     `json:"organization_id"`
	TotalItems   int          `json:"total_items"`
	Items        []BulkItem   `json:"items"`
	Status       JobStatus    `json:"status"`
	Progress     int          `json:"progress"`
	ErrorMessage string       `json:"error_message,omitempty"`
	RetryCount   int          `json:"retry_count"`
	CreatedAt    time.Time    `json:"created_at"`
	UpdatedAt    time.Time    `json:"updated_at"`
	CompletedAt  *time.Time   `json:"completed_at,omitempty"`
}

// getDatabaseConnection returns database connection pool
func (j *BulkImportJob) getDatabaseConnection(ctx context.Context) (*pgxpool.Pool, error) {
	// TODO: Inject database connection via dependency injection
	// For now, this should be passed as parameter
	return nil, fmt.Errorf("database connection not available")
}

// getRedisConnection returns Redis client
func (j *BulkImportJob) getRedisConnection() *redis.Client {
	// TODO: Inject Redis client via dependency injection
	return nil
}

// Process executes the bulk operation with chunked processing
func (j *BulkImportJob) Process(ctx context.Context) error {
	startTime := time.Now()
	ctx, cancel := context.WithTimeout(ctx, MaxJobDuration)
	defer cancel()

	logger.Info("Starting bulk job",
		zap.String("job_id", j.JobID),
		zap.String("job_type", string(j.Type)),
		zap.Int("total_items", j.TotalItems))

	if err := j.updateStatus(StatusProcessing); err != nil {
		return fmt.Errorf("failed to update job status: %w", err)
	}

	batchSize := DefaultBatchSize
	processed := 0
	errors := make([]string, 0)

	for i := 0; i < len(j.Items); i += batchSize {
		select {
		case <-ctx.Done():
			err := ctx.Err()
			logger.Error("Job timeout or cancelled", zap.String("job_id", j.JobID), zap.Error(err))
			return err
		default:
		}

		end := i + batchSize
		if end > len(j.Items) {
			end = len(j.Items)
		}

		chunk := j.Items[i:end]

		// Process chunk based on job type
		var chunkErr error
		switch j.Type {
		case JobBulkAddMembers:
			chunkErr = j.processChunkAddMembers(ctx, chunk)
		case JobBulkTransfer:
			chunkErr = j.processChunkTransfer(ctx, chunk)
		default:
			chunkErr = fmt.Errorf("unsupported job type: %s", j.Type)
		}

		if chunkErr != nil {
			errors = append(errors, fmt.Sprintf("chunk %d failed: %v", i/batchSize+1, chunkErr))
			// Continue processing other chunks instead of failing immediately
			continue
		}

		processed += len(chunk)
		j.Progress = processed

		// Update progress every 10% or at completion
		percentDone := float64(processed) / float64(j.TotalItems) * 100
		if int(percentDone)%10 == 0 || processed == j.TotalItems {
			if err := j.updateProgress(processed, string(StatusProcessing)); err != nil {
				logger.Warn("Failed to update job progress", zap.Error(err))
			}
		}
	}

	// Finalize job
	j.CompletedAt = &startTime
	j.UpdatedAt = time.Now()

	if len(errors) > 0 {
		// Partial success
		j.Status = StatusCompleted // Completed with some failures
		j.ErrorMessage = strings.Join(errors, "; ")
		logger.Warn("Job completed with errors",
			zap.String("job_id", j.JobID),
			zap.Int("successful_items", processed),
			zap.Int("failed_items", len(errors)))
	} else {
		j.Status = StatusCompleted
		logger.Info("Job completed successfully",
			zap.String("job_id", j.JobID),
			zap.Int("processed_items", processed),
			zap.Duration("duration", time.Since(startTime)))
	}

	if err := j.updateStatus(j.Status); err != nil {
		logger.Error("Failed to update final job status", zap.Error(err))
	}

	return nil
}

// processChunkAddMembers processes a chunk of bulk add members operations
func (j *BulkImportJob) processChunkAddMembers(ctx context.Context, chunk []BulkItem) error {
	// This would connect to actual database and perform batch inserts
	// Implementation will be done when service layer integration is complete
	logger.Debug("Processing chunk of bulk add members",
		zap.Int("chunk_size", len(chunk)),
		zap.String("job_id", j.JobID))

	// Placeholder for actual implementation
	// TODO: Implement with database transaction
	return nil
}

// processChunkTransfer processes a chunk of bulk transfer operations
func (j *BulkImportJob) processChunkTransfer(ctx context.Context, chunk []BulkItem) error {
	// This would connect to actual database and perform batch transfers
	// Implementation will be done when service layer integration is complete
	logger.Debug("Processing chunk of bulk transfer",
		zap.Int("chunk_size", len(chunk)),
		zap.String("job_id", j.JobID))

	// Placeholder for actual implementation
	// TODO: Implement with database transaction
	return nil
}

// WithRetry wraps job processing with automatic retry logic using exponential backoff
func (j *BulkImportJob) WithRetry(maxRetries int) error {
	var lastErr error

	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff with jitter
			backoffSeconds := math.Pow(2, float64(attempt-1))
			jitter := rand.Float64() * 0.5 * float64(backoffSeconds)
			waitTime := time.Duration(backoffSeconds+jitter) * time.Second

			logger.Info("Retrying job after backoff",
				zap.String("job_id", j.JobID),
				zap.Int("attempt", attempt),
				zap.Duration("wait_time", waitTime))

			time.Sleep(waitTime)
		}

		// Reset job state before retry
		j.Status = StatusProcessing
		j.RetryCount = attempt

		err := j.Process(context.Background())
		if err == nil {
			return nil // Success
		}

		lastErr = err
		j.ErrorMessage = err.Error()

		logger.Error("Job attempt failed",
			zap.String("job_id", j.JobID),
			zap.Int("attempt", attempt),
			zap.Error(err))

		// Update status for monitoring
		j.updateStatus(StatusFailed)
	}

	// All retries exhausted
	return fmt.Errorf("job failed after %d retries: %w", maxRetries, lastErr)
}

// updateStatus updates the job status in Redis
func (j *BulkImportJob) updateStatus(status JobStatus) error {
	j.Status = status
	j.UpdatedAt = time.Now()

	if j.CompletedAt == nil && (status == StatusCompleted || status == StatusFailed) {
		now := time.Now()
		j.CompletedAt = &now
	}

	jobStore := NewJobStore(nil) // TODO: Pass Redis client properly
	return jobStore.UpdateStatus(j)
}

// updateProgress updates job progress in Redis
func (j *BulkImportJob) updateProgress(processed int, status string) error {
	j.Progress = processed
	j.UpdatedAt = time.Now()

	if status != "" {
		j.Status = JobStatus(status)
	}

	jobStore := NewJobStore(nil) // TODO: Pass Redis client properly
	return jobStore.UpdateProgress(j)
}

// CreateBulkAddJob creates a new bulk add members job
func CreateBulkAddJob(userID, organizationID int64, userIDs []int64, roleIDs []int) *BulkImportJob {
	items := make([]BulkItem, len(userIDs))
	for i, uid := range userIDs {
		items[i] = BulkItem{
			UserID:  uid,
			RoleIDs: roleIDs,
		}
	}

	now := time.Now()
	return &BulkImportJob{
		JobID:            uuid.New().String(),
		Type:             JobBulkAddMembers,
		UserID:           userID,
		OrganizationID:   organizationID,
		TotalItems:       len(userIDs),
		Items:            items,
		Status:           StatusPending,
		Progress:         0,
		RetryCount:       0,
		CreatedAt:        now,
		UpdatedAt:        now,
		CompletedAt:      nil,
		ErrorMessage:     "",
	}
}

// CreateBulkTransferJob creates a new bulk transfer members job
func CreateBulkTransferJob(userID int64, membershipIDs []int64, targetOrgID int64) *BulkImportJob {
	items := make([]BulkItem, len(membershipIDs))
	for i, mid := range membershipIDs {
		items[i] = BulkItem{
			MembershipID: mid,
		}
	}

	now := time.Now()
	return &BulkImportJob{
		JobID:            uuid.New().String(),
		Type:             JobBulkTransfer,
		UserID:           userID,
		OrganizationID:   targetOrgID,
		TotalItems:       len(membershipIDs),
		Items:            items,
		Status:           StatusPending,
		Progress:         0,
		RetryCount:       0,
		CreatedAt:        now,
		UpdatedAt:        now,
		CompletedAt:      nil,
		ErrorMessage:     "",
	}
}

// Consumer function that listens to Kafka topics and processes jobs
// This would be integrated with existing Kafka consumer infrastructure
func StartConsumer(db *pgxpool.Pool, rdb *redis.Client, topic string) {
	// TODO: Integrate with existing Kafka consumer
	// For now, this is a placeholder showing the intended structure
	
	logger.Info("Starting bulk import job consumer",
		zap.String("topic", topic),
		zap.Any("db", db),
		zap.Any("rdb", rdb))

	// Example implementation:
	// kafkaProducer, err := kafka.NewProducer(...)
	// if err != nil { ... }
	// 
	// msgChan := consumeMessages(topic)
	// for msg := range msgChan {
	//     var job BulkImportJob
	//     if err := json.Unmarshal(msg.Value, &job); err != nil {
	//         continue
	//     }
	//     
	//     // Enqueue job for processing
	//     go func() {
	//         _ = job.WithRetry(MaxRetries)
	//     }()
	// }
}

// Helper functions for metrics collection

// RecordJobMetrics records metrics for job execution
func RecordJobMetrics(jobType JobType, duration time.Duration, status JobStatus) {
	logger.Debug("Job metrics recorded",
		zap.String("job_type", string(jobType)),
		zap.Duration("duration", duration),
		zap.String("status", string(status)))
}
