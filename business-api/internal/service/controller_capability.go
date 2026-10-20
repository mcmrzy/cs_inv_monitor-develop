package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/redis/go-redis/v9"
	"inv-api-server/internal/repository"
)

const directDSPProtocol = "direct_uart_03_04_25"

func isACOutputCommand(command string) bool {
	return command == "ac_on" || command == "ac_off"
}

func (s *DeviceService) usesDirectDSP(ctx context.Context, sn string) (bool, error) {
	if s.cache == nil {
		return false, nil
	}
	protocol, err := s.cache.Get(ctx, "device:control:dsp_protocol:"+sn).Result()
	if errors.Is(err, redis.Nil) {
		return false, nil
	} // No evidence yet; retain legacy compatibility.
	if err != nil {
		return false, fmt.Errorf("查询设备控制协议失败: %w", err)
	}
	return strings.TrimSpace(protocol) == directDSPProtocol, nil
}

func (s *DeviceService) checkControllerCommand(ctx context.Context, sn, command string) error {
	if !isACOutputCommand(command) {
		return nil
	}
	direct, err := s.usesDirectDSP(ctx, sn)
	if err != nil {
		return NewCommandError(ErrUnsupportedCommand, "设备控制协议暂不可用", 503)
	}
	if direct {
		return NewCommandError(ErrUnsupportedCommand, "当前控制器尚未支持交流输出开关", 400)
	}
	return nil
}

func (s *DeviceService) restrictControllerCapabilities(ctx context.Context, sn string, caps []repository.CommandCapability) ([]repository.CommandCapability, error) {
	direct, err := s.usesDirectDSP(ctx, sn)
	if err != nil {
		return nil, err
	}
	if direct {
		for i := range caps {
			if isACOutputCommand(caps[i].CommandCode) {
				caps[i].IsEnabled = false
			}
		}
	}
	return caps, nil
}
