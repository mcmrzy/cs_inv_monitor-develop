package service

import (
	"context"
	"errors"
	"fmt"

	dypnsapi "github.com/alibabacloud-go/dypnsapi-20170525/v3/client"
	openapiutil "github.com/alibabacloud-go/darabonba-openapi/v2/utils"
	"github.com/alibabacloud-go/tea/dara"
	"github.com/alibabacloud-go/tea/tea"
	"go.uber.org/zap"

	"inv-api-server/pkg/logger"
)

// SMSProvider 短信发送与验证码校验接口
type SMSProvider interface {
	Send(ctx context.Context, phone, code string) error
	Verify(ctx context.Context, phone, code string) (bool, error)
}

// MockSMSProvider 测试用 mock 实现
type MockSMSProvider struct{}

func (p *MockSMSProvider) Send(ctx context.Context, phone, code string) error {
	return nil
}

func (p *MockSMSProvider) Verify(ctx context.Context, phone, code string) (bool, error) {
	return true, nil
}

// AliyunSMSProvider 阿里云号码认证服务（dypnsapi）实现
type AliyunSMSProvider struct {
	client   *dypnsapi.Client
	signName string
	template string
}

// NewAliyunSMSProvider 创建阿里云号码认证服务 Provider
func NewAliyunSMSProvider(accessKey, secretKey, signName, template string) (*AliyunSMSProvider, error) {
	config := &openapiutil.Config{
		AccessKeyId:     tea.String(accessKey),
		AccessKeySecret: tea.String(secretKey),
		Endpoint:        tea.String("dypnsapi.aliyuncs.com"),
	}
	client, err := dypnsapi.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("create dypnsapi client: %w", err)
	}
	return &AliyunSMSProvider{
		client:   client,
		signName: signName,
		template: template,
	}, nil
}

// Send 通过阿里云号码认证服务发送短信验证码
// 阿里云自动生成验证码并发送，code 参数在此场景下不使用（传空即可）
func (p *AliyunSMSProvider) Send(ctx context.Context, phone, code string) error {
	request := &dypnsapi.SendSmsVerifyCodeRequest{
		PhoneNumber:  tea.String(phone),
		SignName:     tea.String(p.signName),
		TemplateCode: tea.String(p.template),
		// {"code":"##code##"} 让系统自动生成验证码
		TemplateParam: tea.String(`{"code":"##code##"}`),
		CodeType:      tea.Int64(1), // 纯数字验证码
		CodeLength:    tea.Int64(6), // 6位验证码
		ValidTime:     tea.Int64(300), // 5分钟有效
		Interval:      tea.Int64(60),  // 60秒发送间隔
	}

	resp, err := p.client.SendSmsVerifyCode(request)
	if err != nil {
		return fmt.Errorf("SendSmsVerifyCode failed: %w", err)
	}

	if resp.Body == nil || resp.Body.Code == nil || *resp.Body.Code != "OK" {
		msg := "unknown error"
		if resp.Body != nil && resp.Body.Message != nil {
			msg = *resp.Body.Message
		}
		return fmt.Errorf("SendSmsVerifyCode error: %s", msg)
	}

	logger.Info("SMS verification code sent",
		zap.String("phone", maskPhone(phone)),
		zap.String("requestId", dara.StringValue(resp.Body.RequestId)),
	)
	return nil
}

// Verify 通过阿里云号码认证服务校验短信验证码
func (p *AliyunSMSProvider) Verify(ctx context.Context, phone, code string) (bool, error) {
	request := &dypnsapi.CheckSmsVerifyCodeRequest{
		PhoneNumber: tea.String(phone),
		VerifyCode:  tea.String(code),
	}

	resp, err := p.client.CheckSmsVerifyCode(request)
	if err != nil {
		return false, fmt.Errorf("CheckSmsVerifyCode failed: %w", err)
	}

	if resp.Body == nil || resp.Body.Code == nil || *resp.Body.Code != "OK" {
		msg := "unknown error"
		if resp.Body != nil && resp.Body.Message != nil {
			msg = *resp.Body.Message
		}
		return false, fmt.Errorf("CheckSmsVerifyCode error: %s", msg)
	}

	if resp.Body.Model != nil && resp.Body.Model.VerifyResult != nil {
		return *resp.Body.Model.VerifyResult == "PASS", nil
	}

	return false, nil
}

// NewSMSProvider 根据 providerType 创建对应的 SMS Provider
func NewSMSProvider(providerType, accessKey, secretKey, signName, template string) (SMSProvider, error) {
	switch providerType {
	case "aliyun":
		if accessKey == "" || secretKey == "" {
			return nil, errors.New("aliyun sms requires access_key and secret_key")
		}
		return NewAliyunSMSProvider(accessKey, secretKey, signName, template)
	case "mock", "":
		return &MockSMSProvider{}, nil
	default:
		return nil, fmt.Errorf("unknown sms provider: %s", providerType)
	}
}
