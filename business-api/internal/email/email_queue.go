package email

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"inv-api-server/pkg/logger"

	"github.com/google/uuid"
	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// EmailType defines the type of email being sent
type EmailType string

const (
	// Email types
	EmailTypeInvitation   EmailType = "invitation"
	EmailTypeTransfer     EmailType = "transfer_notification"
	EmailTypeWelcome      EmailType = "welcome"
	EmailTypePasswordReset EmailType = "password_reset"
	EmailTypeVerification EmailType = "verification_code"
)

// Priority levels for email jobs
type Priority string

const (
	PriorityHigh   Priority = "high"
	PriorityNormal Priority = "normal"
	PriorityLow    Priority = "low"
)

// EmailJob represents an email sending job in the queue
type EmailJob struct {
	JobID      string                 `json:"job_id"`
	Type       EmailType              `json:"type"`
	ToEmail    string                 `json:"to_email"`
	Subject    string                 `json:"subject"`
	HTMLBody   string                 `json:"html_body,omitempty"`
	TextBody   string                 `json:"text_body,omitempty"`
	Variables  map[string]interface{} `json:"variables,omitempty"` // Template variables
	Priority   Priority               `json:"priority,omitempty"`
	RetryCount int                    `json:"retry_count"`
	CreatedAt  time.Time              `json:"created_at"`
	ExpiresAt  time.Time              `json:"expires_at"`
}

// RateLimiter implements token bucket algorithm for SMTP rate limiting
type RateLimiter struct {
	tokens     chan struct{}
	refillRate time.Duration
	mu         sync.Mutex
	stopCh     chan struct{}
}

// NewRateLimiter creates a new token bucket rate limiter
// maxTokens: maximum capacity of the bucket
// refillRate: how frequently tokens are added (e.g., 100ms for ~10 emails/sec)
func NewRateLimiter(maxTokens int, refillRate time.Duration) *RateLimiter {
	rl := &RateLimiter{
		tokens:     make(chan struct{}, maxTokens),
		refillRate: refillRate,
		stopCh:     make(chan struct{}),
	}

	// Fill initial tokens
	for i := 0; i < maxTokens; i++ {
		rl.tokens <- struct{}{}
	}

	// Start refill goroutine
	go func() {
		ticker := time.NewTicker(refillRate)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				select {
				case rl.tokens <- struct{}{}:
					// Token added
				default:
					// Bucket full, drop token
				}
			case <-rl.stopCh:
				return
			}
		}
	}()

	return rl
}

// Wait blocks until a token is available
func (rl *RateLimiter) Wait() {
	<-rl.tokens
}

// Stop stops the rate limiter
func (rl *RateLimiter) Stop() {
	close(rl.stopCh)
}

// SimpleMetrics tracks email queue metrics
type SimpleMetrics struct {
	mu             sync.RWMutex
	queuedCount    int64
	sentByType     map[EmailType]int64
	failedByType   map[EmailType]int64
	dlqCount       int64
	activeJobs     int64
	totalLatencyMs int64
}

// NewSimpleMetrics creates a new metrics tracker
func NewSimpleMetrics() *SimpleMetrics {
	return &SimpleMetrics{
		sentByType:   make(map[EmailType]int64),
		failedByType: make(map[EmailType]int64),
	}
}

func (m *SimpleMetrics) IncQueued() {
	m.mu.Lock()
	m.queuedCount++
	m.mu.Unlock()
}

func (m *SimpleMetrics) IncSent(emailType EmailType) {
	m.mu.Lock()
	m.sentByType[emailType]++
	m.mu.Unlock()
}

func (m *SimpleMetrics) IncFailed(emailType EmailType, reason string) {
	m.mu.Lock()
	m.failedByType[emailType]++
	m.mu.Unlock()
}

func (m *SimpleMetrics) IncDLQ() {
	m.mu.Lock()
	m.dlqCount++
	m.mu.Unlock()
}

func (m *SimpleMetrics) SetActiveJobs(count int64) {
	m.mu.Lock()
	m.activeJobs = count
	m.mu.Unlock()
}

func (m *SimpleMetrics) AddLatency(latencyMs int64) {
	m.mu.Lock()
	m.totalLatencyMs += latencyMs
	m.mu.Unlock()
}

// EmailQueue handles async email sending via Kafka
type EmailQueue struct {
	kafkaBrokers []string
	topic        string
	dlqTopic     string
	writer       *kafka.Writer
	reader       *kafka.Reader
	rateLimiter  *RateLimiter
	maxRetries   int
	batchSize    int
	batchTimeout time.Duration
	workerCount  int
	shutdownCh   chan struct{}
	wg           sync.WaitGroup
	metrics      *SimpleMetrics
}

// NewEmailQueue creates a new email queue system
func NewEmailQueue(kafkaBrokers []string, topic, dlqTopic string, workers, batchSize int, maxRetries int, rateLimitEPS int) (*EmailQueue, error) {
	if len(kafkaBrokers) == 0 {
		logger.Warn("No Kafka brokers configured, email queue disabled")
		return nil, fmt.Errorf("no kafka brokers configured")
	}

	// Create Kafka writer for publishing
	writer := &kafka.Writer{
		Addr:         kafka.TCP(kafkaBrokers...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		BatchSize:    batchSize,
		BatchTimeout: 5 * time.Second,
		RequiredAcks: kafka.RequireAll,
	}

	// Create rate limiter based on configuration
	// rateLimitEPS: emails per second, so token refill interval is 1/rateLimitEPS seconds
	var refillInterval time.Duration
	if rateLimitEPS > 0 {
		refillInterval = time.Second / time.Duration(rateLimitEPS)
	} else {
		refillInterval = 100 * time.Millisecond // Default: ~10 emails/sec
	}

	// Set bucket capacity slightly higher than burst rate
	bucketCapacity := rateLimitEPS * 5
	if bucketCapacity < 10 {
		bucketCapacity = 10
	}

	rateLimiter := NewRateLimiter(bucketCapacity, refillInterval)

	queue := &EmailQueue{
		kafkaBrokers: kafkaBrokers,
		topic:        topic,
		dlqTopic:     dlqTopic,
		writer:       writer,
		rateLimiter:  rateLimiter,
		maxRetries:   maxRetries,
		batchSize:    batchSize,
		batchTimeout: 5 * time.Second,
		workerCount:  workers,
		shutdownCh:   make(chan struct{}),
		metrics:      NewSimpleMetrics(),
	}

	logger.Info("EmailQueue initialized",
		zap.String("topic", topic),
		zap.Int("workers", workers),
		zap.Int("batch_size", batchSize),
		zap.Int("rate_limit_eps", bucketCapacity),
		zap.Int("max_retries", maxRetries))

	return queue, nil
}

// publish sends an email job to Kafka
func (eq *EmailQueue) publish(job *EmailJob) error {
	msg, err := json.Marshal(job)
	if err != nil {
		eq.metrics.IncFailed(job.Type, "marshal_failed")
		return fmt.Errorf("failed to marshal email job: %w", err)
	}

	err = eq.writer.WriteMessages(context.Background(), kafka.Message{
		Value: msg,
		Key:   []byte(job.JobID), // Use JobID as partition key for ordering
	})

	if err != nil {
		eq.metrics.IncFailed(job.Type, "publish_failed")
		return fmt.Errorf("failed to publish to Kafka: %w", err)
	}

	eq.metrics.IncQueued()
	eq.metrics.SetActiveJobs(eq.metrics.queuedCount)

	logger.Debug("Email job published",
		zap.String("job_id", job.JobID),
		zap.String("type", string(job.Type)),
		zap.String("to", job.ToEmail))

	return nil
}

// SendInvitation adds an invitation email job to the queue
func (eq *EmailQueue) SendInvitation(toEmail, tokenHint, roleName, organizationName string, expiresHours int, senderName string) error {
	job := &EmailJob{
		JobID:   uuid.New().String(),
		Type:    EmailTypeInvitation,
		ToEmail: toEmail,
		Subject: fmt.Sprintf("您已被邀请加入 %s", organizationName),
		Variables: map[string]interface{}{
			"ToEmail":          toEmail,
			"TokenHint":        tokenHint,
			"RoleName":         roleName,
			"OrganizationName": organizationName,
			"ExpiresHours":     fmt.Sprintf("%d", expiresHours),
			"SenderName":       senderName,
		},
		Priority:    PriorityNormal,
		RetryCount:  0,
		CreatedAt:   time.Now(),
		ExpiresAt:   time.Now().Add(24 * time.Hour),
	}

	return eq.publish(job)
}

// SendTransferNotification adds a device transfer notification email
func (eq *EmailQueue) SendTransferNotification(requesterEmail, deviceSN, fromOrg, toOrg, reason, senderName string) error {
	job := &EmailJob{
		JobID:   uuid.New().String(),
		Type:    EmailTypeTransfer,
		ToEmail: requesterEmail,
		Subject: fmt.Sprintf("设备转移通知：%s", deviceSN),
		Variables: map[string]interface{}{
			"DeviceSN":   deviceSN,
			"FromOrg":    fromOrg,
			"ToOrg":      toOrg,
			"Reason":     reason,
			"SenderName": senderName,
		},
		Priority:   PriorityNormal,
		RetryCount: 0,
		CreatedAt:  time.Now(),
		ExpiresAt:  time.Now().Add(7 * 24 * time.Hour),
	}

	return eq.publish(job)
}

// SendWelcomeEmail adds a welcome email job
func (eq *EmailQueue) SendWelcomeEmail(toEmail, username, senderName string) error {
	job := &EmailJob{
		JobID:   uuid.New().String(),
		Type:    EmailTypeWelcome,
		ToEmail: toEmail,
		Subject: "欢迎加入 CSERGY Smart Energy!",
		Variables: map[string]interface{}{
			"ToEmail":    toEmail,
			"Username":   username,
			"SenderName": senderName,
		},
		Priority:   PriorityNormal,
		RetryCount: 0,
		CreatedAt:  time.Now(),
		ExpiresAt:  time.Now().Add(7 * 24 * time.Hour),
	}

	return eq.publish(job)
}

// SendPasswordReset adds a password reset email job
func (eq *EmailQueue) SendPasswordReset(token, username, userEmail, senderName string) error {
	// Only show first 8 chars for security
	tokenDisplay := token
	if len(token) > 8 {
		tokenDisplay = token[:8] + "****"
	}

	job := &EmailJob{
		JobID:   uuid.New().String(),
		Type:    EmailTypePasswordReset,
		ToEmail: userEmail,
		Subject: "密码重置请求",
		Variables: map[string]interface{}{
			"Username":   username,
			"Token":      tokenDisplay,
			"ToEmail":    userEmail,
			"SenderName": senderName,
		},
		Priority:   PriorityHigh,
		RetryCount: 0,
		CreatedAt:  time.Now(),
		ExpiresAt:  time.Now().Add(1 * time.Hour), // Password resets expire quickly
	}

	return eq.publish(job)
}

// SendVerificationCode adds a verification code email job
func (eq *EmailQueue) SendVerificationCode(toEmail, subject, htmlBody string) error {
	job := &EmailJob{
		JobID:     uuid.New().String(),
		Type:      EmailTypeVerification,
		ToEmail:   toEmail,
		Subject:   subject,
		HTMLBody:  htmlBody,
		Priority:  PriorityNormal,
		RetryCount: 0,
		CreatedAt:  time.Now(),
		ExpiresAt:  time.Now().Add(1 * time.Hour),
	}

	return eq.publish(job)
}

// processJob processes a single email job with retry logic and DLQ routing
func (eq *EmailQueue) processJob(job EmailJob) error {
	start := time.Now()

	// Check if expired
	if time.Now().After(job.ExpiresAt) {
		logger.Warn("Email job expired, skipping",
			zap.String("job_id", job.JobID),
			zap.Time("expires_at", job.ExpiresAt),
			zap.Duration("elapsed", time.Since(job.CreatedAt)))

		eq.metrics.IncFailed(job.Type, "expired")
		return nil
	}

	// Apply rate limiting
	eq.rateLimiter.Wait()

	// TODO: Call actual email service implementation
	// For now, simulate successful send
	logger.Info("Processing email job",
		zap.String("job_id", job.JobID),
		zap.String("type", string(job.Type)),
		zap.String("to", job.ToEmail))

	// Simulate success for demo
	eq.metrics.IncSent(job.Type)
	eq.metrics.AddLatency(time.Since(start).Milliseconds())
	eq.metrics.SetActiveJobs(eq.metrics.activeJobs - 1)

	return nil
}

// sendToDeadLetterQueue routes failed emails to DLQ topic
func (eq *EmailQueue) sendToDeadLetterQueue(job *EmailJob, reason string) {
	msg, _ := json.Marshal(job)

	// Create separate writer for DLQ
	dlqWriter := &kafka.Writer{
		Addr:         kafka.TCP(eq.kafkaBrokers...),
		Topic:        eq.dlqTopic,
		RequiredAcks: kafka.RequireAll,
	}
	defer dlqWriter.Close()

	err := dlqWriter.WriteMessages(context.Background(), kafka.Message{
		Key:   []byte(job.JobID),
		Value: msg,
	})

	if err != nil {
		logger.Error("Failed to send to DLQ",
			zap.String("job_id", job.JobID),
			zap.Error(err))
		return
	}

	logger.Warn("Email moved to DLQ",
		zap.String("job_id", job.JobID),
		zap.String("type", string(job.Type)),
		zap.String("reason", reason))

	eq.metrics.IncDLQ()
}

// StartConsumers launches worker pool to consume from internal channel
func (eq *EmailQueue) StartConsumers(jobChan chan EmailJob) {
	logger.Info("Starting email consumers", zap.Int("count", eq.workerCount))

	for i := 0; i < eq.workerCount; i++ {
		eq.wg.Add(1)
		go func(workerID int) {
			defer eq.wg.Done()
			for {
				select {
				case <-eq.shutdownCh:
					logger.Info("Email consumer shutdown", zap.Int("worker", workerID))
					return
				case job, ok := <-jobChan:
					if !ok {
						logger.Info("Email job channel closed")
						return
					}

					if err := eq.processJob(job); err != nil {
						logger.Error("Failed to process email job",
							zap.Int("worker", workerID),
							zap.String("job_id", job.JobID),
							zap.Error(err))

						// Increment retry count
						job.RetryCount++
						if job.RetryCount >= eq.maxRetries {
							// Move to DLQ after max retries exceeded
							reason := fmt.Sprintf("max_retries_exceeded_after_%d_attempts", job.RetryCount)
							eq.sendToDeadLetterQueue(&job, reason)
						} else {
							// Requeue with exponential backoff
							backoff := time.Duration(job.RetryCount*job.RetryCount) * time.Second
							logger.Info("Requeuing email job with backoff",
								zap.String("job_id", job.JobID),
								zap.Duration("backoff", backoff))

							time.Sleep(backoff)
							jobChan <- job
						}
					}
				}
			}
		}(i)
	}
}

// StartKafkaConsumer starts consuming from Kafka topic
func (eq *EmailQueue) StartKafkaConsumer() error {
	if len(eq.kafkaBrokers) == 0 {
		return fmt.Errorf("no kafka brokers configured")
	}

	// Create consumer group reader
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     eq.kafkaBrokers,
		Topic:       eq.topic,
		GroupID:     "inv-api-email-consumer-group",
		StartOffset: kafka.LastOffset,
		MinBytes:    10e3, // 10KB
		MaxBytes:    10e6, // 10MB
	})

	logger.Info("Started Kafka email consumer",
		zap.String("brokers", fmt.Sprintf("%v", eq.kafkaBrokers)),
		zap.String("topic", eq.topic))

	eq.wg.Add(1)
	go func() {
		defer eq.wg.Done()
		defer reader.Close()

		for {
			select {
			case <-eq.shutdownCh:
				return
			default:
				msg, err := reader.ReadMessage(context.Background())
				if err != nil {
					select {
					case <-eq.shutdownCh:
						return
					default:
						logger.Error("Failed to read from Kafka", zap.Error(err))
						time.Sleep(1 * time.Second)
						continue
					}
				}

				var job EmailJob
				if err := json.Unmarshal(msg.Value, &job); err != nil {
					logger.Error("Failed to unmarshal email job",
						zap.Error(err),
						zap.String("data", string(msg.Value)))
					continue
				}

				// Process job directly
				eq.wg.Add(1)
				go func(j EmailJob) {
					defer eq.wg.Done()
					eq.processJob(j)
				}(job)
			}
		}
	}()

	return nil
}

// Publish publishes email jobs to Kafka
func (eq *EmailQueue) Publish(job *EmailJob) error {
	return eq.publish(job)
}

// Shutdown gracefully shuts down the email queue
func (eq *EmailQueue) Shutdown() {
	logger.Info("Shutting down email queue...")

	close(eq.shutdownCh)

	// Wait for workers to finish
	done := make(chan struct{})
	go func() {
		eq.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		logger.Info("Email queue shutdown complete")
	case <-time.After(30 * time.Second):
		logger.Warn("Email queue shutdown timed out")
	}

	// Close Kafka writer
	if eq.writer != nil {
		if err := eq.writer.Close(); err != nil {
			logger.Error("Failed to close Kafka writer", zap.Error(err))
		}
	}

	// Stop rate limiter
	if eq.rateLimiter != nil {
		eq.rateLimiter.Stop()
	}

	logger.Info("Email queue shutdown finished")
}

// GetStats returns current queue statistics
func (eq *EmailQueue) GetStats() map[string]interface{} {
	eq.metrics.mu.RLock()
	defer eq.metrics.mu.RUnlock()

	return map[string]interface{}{
		"active_jobs":    eq.metrics.activeJobs,
		"queued_count":   eq.metrics.queuedCount,
		"dlq_size":       eq.metrics.dlqCount,
		"sent_by_type":   eq.metrics.sentByType,
		"failed_by_type": eq.metrics.failedByType,
		"kafka_brokers":  eq.kafkaBrokers,
		"max_retries":    eq.maxRetries,
		"worker_count":   eq.workerCount,
		"batch_size":     eq.batchSize,
	}
}
