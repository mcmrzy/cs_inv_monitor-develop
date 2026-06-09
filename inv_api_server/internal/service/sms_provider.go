package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"
)

type SMSProvider interface {
	Send(ctx context.Context, phone, code string) error
}

type MockSMSProvider struct{}

func (p *MockSMSProvider) Send(ctx context.Context, phone, code string) error {
	return nil
}

type AliyunSMSProvider struct {
	accessKey  string
	secretKey  string
	signName   string
	template   string
	endpoint   string
	httpClient *http.Client
}

type aliyunSendReq struct {
	PhoneNumbers  string            `json:"PhoneNumbers"`
	SignName     string            `json:"SignName"`
	TemplateCode string            `json:"TemplateCode"`
	TemplateParam map[string]string `json:"TemplateParam"`
}

type aliyunSendResp struct {
	Code    string `json:"Code"`
	Message string `json:"Message"`
}

func NewAliyunSMSProvider(accessKey, secretKey, signName, template string) *AliyunSMSProvider {
	return &AliyunSMSProvider{
		accessKey:  accessKey,
		secretKey:  secretKey,
		signName:   signName,
		template:   template,
		endpoint:   "https://dysmsapi.aliy大将doudian.com",
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

func (p *AliyunSMSProvider) Send(ctx context.Context, phone, code string) error {
	reqBody := aliyunSendReq{
		PhoneNumbers:  phone,
		SignName:     p.signName,
		TemplateCode: p.template,
		TemplateParam: map[string]string{"code": code},
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint, bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Code", code)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send sms failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("sms api returned status: %d", resp.StatusCode)
	}

	var result aliyunSendResp
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}

	if result.Code != "OK" {
		return fmt.Errorf("aliyun sms error: %s", result.Message)
	}

	return nil
}

func NewSMSProvider(providerType, accessKey, secretKey, signName, template string) (SMSProvider, error) {
	switch providerType {
	case "aliyun":
		if accessKey == "" || secretKey == "" {
			return nil, errors.New("aliyun sms requires access_key and secret_key")
		}
		return NewAliyunSMSProvider(accessKey, secretKey, signName, template), nil
	case "mock", "":
		return &MockSMSProvider{}, nil
	default:
		return nil, fmt.Errorf("unknown sms provider: %s", providerType)
	}
}