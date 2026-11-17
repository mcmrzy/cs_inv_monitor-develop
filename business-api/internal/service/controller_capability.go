package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/redis/go-redis/v9"
	"inv-api-server/internal/repository"
)

const (
	directDSPProtocol        = "direct_uart_03_04_25"
	modbusDSPProtocol        = "modbus_rtu_v1.27"
	modbusPowerProtocol      = modbusDSPProtocol + ":ac_power"
	modbusPowerMinFirmware   = "0.4.47-modbus-full"
	modbusBatteryProtocol    = modbusPowerProtocol + ":battery_settings"
	modbusBatteryMinFirmware = "0.4.53-modbus-full"
	modbusSystemProtocol     = modbusBatteryProtocol + ":system_settings"
	modbusInputAlarm         = "set_modbus_input_change_alarm"
)

func isACOutputCommand(command string) bool {
	return command == "ac_on" || command == "ac_off"
}

func supportsModbusPower(protocol string) bool {
	return protocol == modbusPowerProtocol || supportsModbusBattery(protocol)
}

func supportsModbusBattery(protocol string) bool {
	return protocol == modbusBatteryProtocol || protocol == modbusSystemProtocol
}

func isModbusSystemCommand(command string) bool {
	switch command {
	case "set_modbus_power_saving", "set_modbus_auto_frequency",
		"set_modbus_battery_open_alarm", "set_modbus_inverter_mute":
		return true
	default:
		return false
	}
}

func isBatterySettingCommand(command string) bool {
	switch command {
	case "set_soc_cutoff", "set_soc_back_utl", "set_soc_back_bat",
		"set_equalize_enable", "set_equalize_voltage", "set_equalize_time",
		"set_equalize_timeout", "set_equalize_interval":
		return true
	default:
		return false
	}
}

func requiresModbusBatterySettings(cap repository.CommandCapability) bool {
	return cap.MinFirmware != nil && *cap.MinFirmware == modbusBatteryMinFirmware &&
		isBatterySettingCommand(cap.CommandCode)
}

func (s *DeviceService) controllerProtocol(ctx context.Context, sn string) (string, error) {
	if s.cache == nil {
		return "", nil
	}
	protocol, err := s.cache.Get(ctx, "device:control:dsp_protocol:"+sn).Result()
	if errors.Is(err, redis.Nil) {
		return "", nil
	} // No evidence yet; retain legacy compatibility.
	if err != nil {
		return "", fmt.Errorf("查询设备控制协议失败: %w", err)
	}
	return strings.TrimSpace(protocol), nil
}

func (s *DeviceService) checkControllerCommand(ctx context.Context, sn, command string) error {
	if isBatterySettingCommand(command) && s.modelRepo != nil {
		cap, err := s.getCommandCapability(ctx, sn, command)
		if err != nil {
			return NewCommandError(ErrUnsupportedCommand, "当前设备型号未启用此电池设置", 400)
		}
		if requiresModbusBatterySettings(*cap) {
			protocol, err := s.controllerProtocol(ctx, sn)
			if err != nil {
				return NewCommandError(ErrUnsupportedCommand, "设备控制协议暂不可用", 503)
			}
			if !supportsModbusBattery(protocol) {
				return NewCommandError(ErrUnsupportedCommand, "当前通讯板未报告电池设置回读能力", 400)
			}
		}
	}
	systemCommand := isModbusSystemCommand(command)
	if !isACOutputCommand(command) && command != modbusInputAlarm && !systemCommand {
		return nil
	}
	protocol, err := s.controllerProtocol(ctx, sn)
	if err != nil {
		return NewCommandError(ErrUnsupportedCommand, "设备控制协议暂不可用", 503)
	}
	if systemCommand {
		if protocol != modbusSystemProtocol {
			return NewCommandError(ErrUnsupportedCommand, "当前通讯板未报告系统设置回读能力", 400)
		}
		return nil
	}
	if command == modbusInputAlarm {
		if !supportsModbusPower(protocol) {
			return NewCommandError(ErrUnsupportedCommand, "当前通讯板尚未支持主输入变化告警设置", 400)
		}
		return nil
	}
	if protocol == directDSPProtocol {
		return NewCommandError(ErrUnsupportedCommand, "当前控制器尚未支持交流输出开关", 400)
	}
	if protocol == modbusDSPProtocol {
		return NewCommandError(ErrUnsupportedCommand, "当前 Modbus 通讯板未报告云端开关机能力", 400)
	}
	if s.modelRepo != nil {
		capability, err := s.getCommandCapability(ctx, sn, command)
		if supportsModbusPower(protocol) && (err != nil || !capability.IsEnabled) {
			return NewCommandError(ErrUnsupportedCommand, "当前设备型号未启用开关机命令", 400)
		}
		if err == nil && requiresModbusPower(*capability) && !supportsModbusPower(protocol) {
			return NewCommandError(ErrUnsupportedCommand, "当前 Modbus 通讯板未报告云端开关机能力", 400)
		}
	}
	return nil
}

func requiresModbusPower(cap repository.CommandCapability) bool {
	return isACOutputCommand(cap.CommandCode) && cap.MinFirmware != nil && *cap.MinFirmware == modbusPowerMinFirmware
}

func (s *DeviceService) restrictControllerCapabilities(ctx context.Context, sn string, caps []repository.CommandCapability) ([]repository.CommandCapability, error) {
	protocol, err := s.controllerProtocol(ctx, sn)
	if err != nil {
		return nil, err
	}
	for i := range caps {
		capability := caps[i]
		if (isACOutputCommand(capability.CommandCode) &&
			(protocol == directDSPProtocol || protocol == modbusDSPProtocol ||
				(requiresModbusPower(capability) && !supportsModbusPower(protocol)))) ||
			(capability.CommandCode == modbusInputAlarm && !supportsModbusPower(protocol)) ||
			(requiresModbusBatterySettings(capability) && !supportsModbusBattery(protocol)) ||
			(isModbusSystemCommand(capability.CommandCode) && protocol != modbusSystemProtocol) {
			caps[i].IsEnabled = false
		}
	}
	return caps, nil
}
