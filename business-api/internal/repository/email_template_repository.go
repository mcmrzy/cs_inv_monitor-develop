package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EmailTemplate 系统邮件模板（email_templates 表）。
// html_body 存放「内容块」HTML（Go template 语法占位变量），
// 渲染时由邮件服务套上统一品牌信封（信封不可通过该表定制）。
type EmailTemplate struct {
	TemplateKey string    `json:"template_key"`
	Subject     string    `json:"subject"`
	HTMLBody    string    `json:"html_body"`
	Enabled     bool      `json:"enabled"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// EmailTemplateRepository 邮件模板存取。
type EmailTemplateRepository struct {
	db *pgxpool.Pool
}

func NewEmailTemplateRepository(db *pgxpool.Pool) *EmailTemplateRepository {
	return &EmailTemplateRepository{db: db}
}

// List 查询全部邮件模板（按 template_key 排序）。
func (r *EmailTemplateRepository) List(ctx context.Context) ([]EmailTemplate, error) {
	rows, err := r.db.Query(ctx, `
		SELECT template_key, subject, html_body, enabled, updated_at
		FROM email_templates
		ORDER BY template_key
	`)
	if err != nil {
		return nil, fmt.Errorf("查询邮件模板列表: %w", err)
	}
	defer rows.Close()

	result := make([]EmailTemplate, 0)
	for rows.Next() {
		var t EmailTemplate
		if err := rows.Scan(&t.TemplateKey, &t.Subject, &t.HTMLBody, &t.Enabled, &t.UpdatedAt); err != nil {
			return nil, fmt.Errorf("扫描邮件模板行: %w", err)
		}
		result = append(result, t)
	}
	return result, rows.Err()
}

// Get 按 template_key 查询单个模板；不存在返回 (nil, nil)。
func (r *EmailTemplateRepository) Get(ctx context.Context, templateKey string) (*EmailTemplate, error) {
	var t EmailTemplate
	err := r.db.QueryRow(ctx, `
		SELECT template_key, subject, html_body, enabled, updated_at
		FROM email_templates
		WHERE template_key = $1
	`, templateKey).Scan(&t.TemplateKey, &t.Subject, &t.HTMLBody, &t.Enabled, &t.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("查询邮件模板 %s: %w", templateKey, err)
	}
	return &t, nil
}

// Upsert 更新（或补建）指定模板的主题、内容块与启用状态。
func (r *EmailTemplateRepository) Upsert(ctx context.Context, t *EmailTemplate) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO email_templates (template_key, subject, html_body, enabled, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (template_key) DO UPDATE SET
			subject = EXCLUDED.subject,
			html_body = EXCLUDED.html_body,
			enabled = EXCLUDED.enabled,
			updated_at = NOW()
	`, t.TemplateKey, t.Subject, t.HTMLBody, t.Enabled)
	if err != nil {
		return fmt.Errorf("保存邮件模板 %s: %w", t.TemplateKey, err)
	}
	return nil
}
