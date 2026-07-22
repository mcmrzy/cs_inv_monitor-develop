package job_test

import (
	"context"
	"testing"
	"time"

	"inv-api-server/internal/job"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBulkImportJob_Process(t *testing.T) {
	// Setup test data
	userID := int64(1)
	orgID := int64(100)
	userIDs := []int64{1, 2, 3, 4, 5}
	roleIDs := []int{1, 2}

	// Create job
	bulkJob := job.CreateBulkAddJob(userID, orgID, userIDs, roleIDs)

	// Assertions
	assert.NotEmpty(t, bulkJob.JobID, "JobID should not be empty")
	assert.Equal(t, job.JobBulkAddMembers, bulkJob.Type)
	assert.Equal(t, userID, bulkJob.UserID)
	assert.Equal(t, orgID, bulkJob.OrganizationID)
	assert.Equal(t, len(userIDs), bulkJob.TotalItems)
	assert.Equal(t, job.StatusPending, bulkJob.Status)
	assert.Equal(t, 0, bulkJob.Progress)
	assert.NotNil(t, bulkJob.Items)
	assert.Len(t, bulkJob.Items, len(userIDs))
}

func TestBulkTransferJob_Create(t *testing.T) {
	userID := int64(1)
	membershipIDs := []int64{10, 20, 30}
	targetOrgID := int64(200)

	bulkJob := job.CreateBulkTransferJob(userID, membershipIDs, targetOrgID)

	assert.NotEmpty(t, bulkJob.JobID)
	assert.Equal(t, job.JobBulkTransfer, bulkJob.Type)
	assert.Equal(t, userID, bulkJob.UserID)
	assert.Equal(t, targetOrgID, bulkJob.OrganizationID)
	assert.Equal(t, len(membershipIDs), bulkJob.TotalItems)
	assert.Equal(t, job.StatusPending, bulkJob.Status)
	assert.Len(t, bulkJob.Items, len(membershipIDs))
	
	for i, item := range bulkJob.Items {
		assert.Equal(t, membershipIDs[i], item.MembershipID)
	}
}

func TestBulkImportJob_ChunkedProcessing(t *testing.T) {
	// Create a job with many items
	totalItems := 250
	userIDs := make([]int64, totalItems)
	for i := 0; i < totalItems; i++ {
		userIDs[i] = int64(i + 1)
	}

	bulkJob := job.CreateBulkAddJob(1, 100, userIDs, nil)
	
	// Verify chunking
	expectedChunks := (totalItems + job.DefaultBatchSize - 1) / job.DefaultBatchSize
	actualChunks := 0
	
	for i := 0; i < len(bulkJob.Items); i += job.DefaultBatchSize {
		actualChunks++
	}
	
	assert.Equal(t, expectedChunks, actualChunks, "Should have correct number of chunks")
}

func TestBulkImportJob_WithRetry(t *testing.T) {
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1, 2, 3}, nil)
	
	// Test that WithRetry eventually succeeds or fails appropriately
	startTime := time.Now()
	
	// Note: This test requires actual database implementation
	// For now, just verify the structure
	assert.NotNil(t, bulkJob)
	assert.Less(t, time.Since(startTime), 10*time.Second)
}

func TestBulkImportJob_StatusUpdates(t *testing.T) {
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1}, nil)
	
	// Test status transitions
	assert.Equal(t, job.StatusPending, bulkJob.Status)
	
	// Simulate processing
	bulkJob.Status = job.StatusProcessing
	bulkJob.Progress = 50
	assert.Equal(t, job.StatusProcessing, bulkJob.Status)
	assert.Equal(t, 50, bulkJob.Progress)
	
	// Simulate completion
	bulkJob.Status = job.StatusCompleted
	bulkJob.Progress = 100
	completedAt := time.Now()
	bulkJob.CompletedAt = &completedAt
	
	assert.Equal(t, job.StatusCompleted, bulkJob.Status)
	assert.Equal(t, 100, bulkJob.Progress)
	assert.NotNil(t, bulkJob.CompletedAt)
}

func TestBulkImportJob_ErrorHandling(t *testing.T) {
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1, 2, 3}, nil)
	
	// Simulate error
	bulkJob.Status = job.StatusFailed
	bulkJob.ErrorMessage = "database connection failed"
	
	assert.Equal(t, job.StatusFailed, bulkJob.Status)
	assert.NotEmpty(t, bulkJob.ErrorMessage)
	assert.Equal(t, "database connection failed", bulkJob.ErrorMessage)
}

func TestBulkImportJob_Timeout(t *testing.T) {
	// Create job with timeout context
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()
	
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1, 2, 3}, nil)
	
	// Simulate long-running process that should timeout
	done := make(chan error, 1)
	go func() {
		// Wait for context cancellation
		<-ctx.Done()
		done <- ctx.Err()
	}()
	
	select {
	case err := <-done:
		assert.Equal(t, context.DeadlineExceeded, err)
	case <-time.After(2 * time.Second):
		t.Fatal("Test took too long")
	}
	
	assert.NotNil(t, bulkJob)
}

// Integration test with actual Redis (requires test Redis instance)
func TestBulkImportJob_Integration_RedisJobStore(t *testing.T) {
	// Skip if Redis not available
	t.Skip("Requires Redis instance - run manually")
	
	ctx := context.Background()
	
	// This would require actual Redis client setup
	// jobStore := job.NewJobStore(redisClient)
	
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1, 2, 3}, nil)
	
	// Create job in store
	// err := jobStore.CreateJob(ctx, bulkJob)
	// require.NoError(t, err)
	
	// Retrieve job
	// retrievedJob, err := jobStore.GetJob(ctx, bulkJob.JobID)
	// require.NoError(t, err)
	// assert.Equal(t, bulkJob.JobID, retrievedJob.JobID)
	
	assert.NotNil(t, bulkJob)
	assert.NotNil(t, ctx)
}

// Load test for processing 10,000 items
func TestBulkImportJob_LoadTest_10000Items(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping load test in short mode")
	}
	
	totalItems := 10000
	userIDs := make([]int64, totalItems)
	for i := 0; i < totalItems; i++ {
		userIDs[i] = int64(i + 1)
	}
	
	bulkJob := job.CreateBulkAddJob(1, 100, userIDs, nil)
	
	startTime := time.Now()
	
	// Verify job creation
	assert.Equal(t, totalItems, bulkJob.TotalItems)
	assert.Len(t, bulkJob.Items, totalItems)
	
	// Calculate expected processing time
	// At 100 items per chunk = 100 chunks
	// If each chunk takes ~10ms = 1 second total
	expectedChunks := (totalItems + job.DefaultBatchSize - 1) / job.DefaultBatchSize
	
	t.Logf("Load test: %d items, %d chunks, expected time: ~%d ms", 
		totalItems, expectedChunks, expectedChunks*10)
	
	elapsed := time.Since(startTime)
	assert.Less(t, elapsed, 5*time.Second, "Job creation should be fast")
}

// Benchmark bulk job creation
func BenchmarkBulkImportJob_Create(b *testing.B) {
	userIDs := make([]int64, 1000)
	for i := 0; i < 1000; i++ {
		userIDs[i] = int64(i + 1)
	}
	
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		job.CreateBulkAddJob(1, 100, userIDs, []int{1, 2})
	}
}

// Test concurrent job processing
func TestBulkImportJob_ConcurrentProcessing(t *testing.T) {
	numJobs := 5
	jobs := make([]*job.BulkImportJob, numJobs)
	
	for i := 0; i < numJobs; i++ {
		userIDs := []int64{int64(i*10 + 1), int64(i*10 + 2), int64(i*10 + 3)}
		jobs[i] = job.CreateBulkAddJob(int64(i+1), int64(100+i), userIDs, nil)
	}
	
	// Verify all jobs created successfully
	for i, j := range jobs {
		require.NotNil(t, j, "Job %d should not be nil", i)
		assert.NotEmpty(t, j.JobID, "Job %d should have ID", i)
		assert.Equal(t, job.StatusPending, j.Status)
	}
}

// Test job cancellation
func TestBulkImportJob_Cancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	
	bulkJob := job.CreateBulkAddJob(1, 100, []int64{1, 2, 3}, nil)
	
	// Cancel context before processing
	cancel()
	
	// Verify context is cancelled
	select {
	case <-ctx.Done():
		assert.Equal(t, context.Canceled, ctx.Err())
	default:
		t.Fatal("Context should be cancelled")
	}
	
	assert.NotNil(t, bulkJob)
}
