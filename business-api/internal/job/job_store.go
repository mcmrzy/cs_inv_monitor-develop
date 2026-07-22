package job

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const (
	jobStatusKeyPrefix    = "bulk_job:"
	jobStatusTTL          = 24 * time.Hour // Jobs stay in Redis for 24 hours
	progressUpdateFreq    = 10             // Update every 10%
	pendingJobsKey        = "bulk_jobs:pending"
	runningJobsKey        = "bulk_jobs:running"
	completedJobsKey      = "bulk_jobs:completed"
	failedJobsKey         = "bulk_jobs:failed"
)

// JobStore manages bulk operation job persistence using Redis
type JobStore struct {
	rdb *redis.Client
}

// NewJobStore creates a new Redis-based job store
func NewJobStore(rdb *redis.Client) *JobStore {
	return &JobStore{rdb: rdb}
}

// CreateJob stores a new job in Redis
func (s *JobStore) CreateJob(ctx context.Context, j *BulkImportJob) error {
	key := fmt.Sprintf("%s%s", jobStatusKeyPrefix, j.JobID)

	data, err := json.Marshal(j)
	if err != nil {
		return fmt.Errorf("marshal job data: %w", err)
	}

	pipe := s.rdb.Pipeline()
	pipe.Set(ctx, key, string(data), jobStatusTTL)

	// Add to pending jobs list
	pipe.LPush(ctx, pendingJobsKey, j.JobID)
	pipe.Expire(ctx, pendingJobsKey, jobStatusTTL)

	_, err = pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("exec pipeline: %w", err)
	}

	logger.Info("Job created and stored",
		zap.String("job_id", j.JobID),
		zap.String("job_type", string(j.Type)),
		zap.Int("total_items", j.TotalItems))

	return nil
}

// GetJob retrieves a job from Redis by ID
func (s *JobStore) GetJob(ctx context.Context, jobID string) (*BulkImportJob, error) {
	key := fmt.Sprintf("%s%s", jobStatusKeyPrefix, jobID)

	data, err := s.rdb.Get(ctx, key).Bytes()
	if err != nil {
		if err == redis.Nil {
			return nil, fmt.Errorf("job not found: %s", jobID)
		}
		return nil, fmt.Errorf("get job from redis: %w", err)
	}

	var j BulkImportJob
	if err := json.Unmarshal(data, &j); err != nil {
		return nil, fmt.Errorf("unmarshal job data: %w", err)
	}

	return &j, nil
}

// GetPendingJobs retrieves all pending job IDs
func (s *JobStore) GetPendingJobs(ctx context.Context) ([]string, error) {
	return s.rdb.LRange(ctx, pendingJobsKey, 0, -1).Result()
}

// GetRunningJobs retrieves all running job IDs
func (s *JobStore) GetRunningJobs(ctx context.Context) ([]string, error) {
	return s.rdb.LRange(ctx, runningJobsKey, 0, -1).Result()
}

// GetCompletedJobs retrieves all completed job IDs
func (s *JobStore) GetCompletedJobs(ctx context.Context, count int64) ([]string, error) {
	if count <= 0 {
		count = 100 // Default: last 100 jobs
	}
	return s.rdb.LRange(ctx, completedJobsKey, -count, -1).Result()
}

// GetFailedJobs retrieves all failed job IDs
func (s *JobStore) GetFailedJobs(ctx context.Context, count int64) ([]string, error) {
	if count <= 0 {
		count = 100 // Default: last 100 jobs
	}
	return s.rdb.LRange(ctx, failedJobsKey, -count, -1).Result()
}

// UpdateStatus updates the job status in Redis and moves it between queues
func (s *JobStore) UpdateStatus(j *BulkImportJob) error {
	ctx := context.Background()
	key := fmt.Sprintf("%s%s", jobStatusKeyPrefix, j.JobID)

	data, err := json.Marshal(j)
	if err != nil {
		return fmt.Errorf("marshal job data: %w", err)
	}

	pipe := s.rdb.Pipeline()

	// Update job data
	pipe.Set(ctx, key, string(data), jobStatusTTL)

	// Move to appropriate queue based on status
	switch j.Status {
	case StatusPending:
		pipe.LPush(ctx, pendingJobsKey, j.JobID)
		s.removeFromQueues(pipe, j.JobID, []string{runningJobsKey, completedJobsKey, failedJobsKey})
	case StatusProcessing:
		pipe.LPush(ctx, runningJobsKey, j.JobID)
		s.removeFromQueues(pipe, j.JobID, []string{pendingJobsKey, completedJobsKey, failedJobsKey})
	case StatusCompleted:
		pipe.LPush(ctx, completedJobsKey, j.JobID)
		s.removeFromQueues(pipe, j.JobID, []string{pendingJobsKey, runningJobsKey, failedJobsKey})
	case StatusFailed:
		pipe.LPush(ctx, failedJobsKey, j.JobID)
		s.removeFromQueues(pipe, j.JobID, []string{pendingJobsKey, runningJobsKey, completedJobsKey})
	case StatusCancelled:
		s.removeFromQueues(pipe, j.JobID, []string{pendingJobsKey, runningJobsKey, completedJobsKey, failedJobsKey})
	}

	_, err = pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("update job status pipeline: %w", err)
	}

	logger.Debug("Job status updated",
		zap.String("job_id", j.JobID),
		zap.String("status", string(j.Status)))

	return nil
}

// removeFromQueues removes a job ID from specified queues
func (s *JobStore) removeFromQueues(pipe redis.Pipeliner, jobID string, queues []string) {
	ctx := context.Background()
	for _, q := range queues {
		// LREM removes all occurrences of value from list
		pipe.LRem(ctx, q, -1, jobID)
	}
}

// UpdateProgress updates job progress in Redis
func (s *JobStore) UpdateProgress(j *BulkImportJob) error {
	ctx := context.Background()
	key := fmt.Sprintf("%s%s:progress", jobStatusKeyPrefix, j.JobID)

	// Store simple progress data as hash
	pipe := s.rdb.Pipeline()
	pipe.HSet(ctx, key, map[string]interface{}{
		"processed":  j.Progress,
		"total":      j.TotalItems,
		"status":     j.Status,
		"updated_at": j.UpdatedAt.Unix(),
	})
	pipe.Expire(ctx, key, jobStatusTTL)

	_, err := pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("update job progress: %w", err)
	}

	logger.Debug("Job progress updated",
		zap.String("job_id", j.JobID),
		zap.Int("processed", j.Progress),
		zap.Int("total", j.TotalItems))

	return nil
}

// GetProgress retrieves current progress for a job
func (s *JobStore) GetProgress(ctx context.Context, jobID string) (int, int, string, error) {
	key := fmt.Sprintf("%s%s:progress", jobStatusKeyPrefix, jobID)

	data, err := s.rdb.HGetAll(ctx, key).Result()
	if err != nil {
		if err == redis.Nil {
			// Fallback to full job data if progress hash doesn't exist
			j, err := s.GetJob(ctx, jobID)
			if err != nil {
				return 0, 0, "", err
			}
			return j.Progress, j.TotalItems, string(j.Status), nil
		}
		return 0, 0, "", fmt.Errorf("get job progress: %w", err)
	}

	var processed, total int
	fmt.Sscanf(data["processed"], "%d", &processed)
	fmt.Sscanf(data["total"], "%d", &total)

	return processed, total, data["status"], nil
}

// JobStats returns statistics about bulk jobs
type JobStats struct {
	PendingCount   int64 `json:"pending_count"`
	RunningCount   int64 `json:"running_count"`
	CompletedCount int64 `json:"completed_count"`
	FailedCount    int64 `json:"failed_count"`
	TotalProcessed int64 `json:"total_processed"`
}

// GetStats retrieves comprehensive job statistics
func (s *JobStore) GetStats(ctx context.Context) (*JobStats, error) {
	stats := &JobStats{}

	var err error
	stats.PendingCount, err = s.rdb.LLen(ctx, pendingJobsKey).Result()
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("get pending count: %w", err)
	}

	stats.RunningCount, err = s.rdb.LLen(ctx, runningJobsKey).Result()
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("get running count: %w", err)
	}

	stats.CompletedCount, err = s.rdb.LLen(ctx, completedJobsKey).Result()
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("get completed count: %w", err)
	}

	stats.FailedCount, err = s.rdb.LLen(ctx, failedJobsKey).Result()
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("get failed count: %w", err)
	}

	// Calculate total processed
	stats.TotalProcessed = stats.CompletedCount + stats.FailedCount

	return stats, nil
}

// DeleteJob permanently removes a job from Redis
func (s *JobStore) DeleteJob(ctx context.Context, jobID string) error {
	key := fmt.Sprintf("%s%s", jobStatusKeyPrefix, jobID)
	progressKey := fmt.Sprintf("%s%s:progress", jobStatusKeyPrefix, jobID)

	pipe := s.rdb.Pipeline()
	pipe.Del(ctx, key)
	pipe.Del(ctx, progressKey)
	pipe.LRem(ctx, pendingJobsKey, -1, jobID)
	pipe.LRem(ctx, runningJobsKey, -1, jobID)
	pipe.LRem(ctx, completedJobsKey, -1, jobID)
	pipe.LRem(ctx, failedJobsKey, -1, jobID)

	_, err := pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("delete job from redis: %w", err)
	}

	return nil
}

// CleanupOldJobs removes jobs older than specified duration
func (s *JobStore) CleanupOldJobs(ctx context.Context, olderThan time.Duration) (int, error) {
	cutoffTime := time.Now().Add(-olderThan)
	count := 0

	// Get all job queues
	queues := []string{pendingJobsKey, runningJobsKey, completedJobsKey, failedJobsKey}

	for _, queue := range queues {
		jobIDs, err := s.rdb.LRange(ctx, queue, 0, -1).Result()
		if err != nil {
			continue
		}

		for _, jobID := range jobIDs {
			j, err := s.GetJob(ctx, jobID)
			if err != nil || j.CreatedAt.After(cutoffTime) {
				continue
			}

			if err := s.DeleteJob(ctx, jobID); err == nil {
				count++
			}
		}
	}

	if count > 0 {
		logger.Info("Cleaned up old jobs",
			zap.Int("jobs_removed", count),
			zap.Duration("older_than", olderThan))
	}

	return count, nil
}

// SubscribeToJobProgress creates a channel to listen for job progress updates
func (s *JobStore) SubscribeToJobProgress(ctx context.Context, jobID string) <-chan string {
	// TODO: Implement Pub/Sub channel for real-time updates
	// For now, return a channel that clients can use to poll updates
	updateChannel := make(chan string, 10)

	go func() {
		defer close(updateChannel)
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				processed, total, status, err := s.GetProgress(ctx, jobID)
				if err != nil {
					continue
				}

				msg := fmt.Sprintf(`{"job_id":"%s","progress":%d,"total":%d,"status":"%s"}`,
					jobID, processed, total, status)
				updateChannel <- msg
			}
		}
	}()

	return updateChannel
}
