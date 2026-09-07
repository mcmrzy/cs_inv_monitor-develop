package service

import (
	"encoding/json"
	"reflect"
	"testing"

	"inv-device-server/internal/model"

	"github.com/stretchr/testify/require"
)

// V2.1 契约测试：internalDeviceInfoRequest（device-comm 内部请求）与
// model.DeviceInfo（cs_inv/{sn}/info 主题）的 JSON 键名必须完全对齐，
// 保证 registry 序列化主路径与 postInternal 兜底路径一致。
func TestDeviceInfoContractKeyAlignment(t *testing.T) {
	info := model.DeviceInfo{
		SN: "L10TEST001", Model: "CS-L10-6K2", Manufacturer: "CSA",
		FirmwareARM: "1.2.3", FirmwareESP: "0.9.0", FirmwareDSP: "", FirmwareBMS: "",
		Type: "off_grid_inverter", RatedPower: 6000, RatedVoltage: 230, RatedFreq: 50,
		BatteryVoltage: 51.2, BatteryType: "LiFePO4", CellCount: 0, TempSensorCount: 0,
		// V2.1 新增 4 只读字段
		Phase: "single", InverterModule: "L10-2026-0001", HardwareVersion: "HW-2.1", BootloaderVersion: "BL-1.0",
	}
	infoJSON, err := json.Marshal(info)
	require.NoError(t, err)

	var raw map[string]any
	require.NoError(t, json.Unmarshal(infoJSON, &raw))
	infoKeys := make([]string, 0, len(raw))
	for k := range raw {
		infoKeys = append(infoKeys, k)
	}

	req := internalDeviceInfoRequest{
		SN: info.SN, Model: info.Model, Manufacturer: info.Manufacturer,
		FirmwareARM: info.FirmwareARM, FirmwareESP: info.FirmwareESP,
		FirmwareDSP: info.FirmwareDSP, FirmwareBMS: info.FirmwareBMS,
		Type: info.Type, RatedPower: float64(info.RatedPower), RatedPowerW: info.RatedPower,
		RatedVoltage: float64(info.RatedVoltage), RatedFreq: info.RatedFreq,
		BatteryVoltage: info.BatteryVoltage, BatteryType: info.BatteryType,
		CellCount: info.CellCount, TempSensorCount: info.TempSensorCount,
		Phase: info.Phase, InverterModule: info.InverterModule,
		HardwareVersion: info.HardwareVersion, BootloaderVersion: info.BootloaderVersion,
	}
	reqJSON, err := json.Marshal(req)
	require.NoError(t, err)

	var reqRaw map[string]any
	require.NoError(t, json.Unmarshal(reqJSON, &reqRaw))
	reqKeys := make([]string, 0, len(reqRaw))
	for k := range reqRaw {
		reqKeys = append(reqKeys, k)
	}

	// internalDeviceInfoRequest 是 DeviceInfo 的超集（多 rated_power_w 落库列专用键），
	// 但 DeviceInfo 的每个契约键必须原样保留——registry 主路径与 postInternal 兜底路径共用。
	reqKeySet := make(map[string]bool, len(reqKeys))
	for _, k := range reqKeys {
		reqKeySet[k] = true
	}
	for _, k := range infoKeys {
		require.True(t, reqKeySet[k], "internalDeviceInfoRequest 缺少契约键 %s", k)
	}
	require.Len(t, reqKeys, len(infoKeys)+1) // 仅允许 rated_power_w 一个额外键
	require.Contains(t, reqKeys, "rated_power_w")
}

// V2.1 新增 4 字段透传：DeviceInfo → internalDeviceInfoRequest 全字段值一致。
func TestDeviceInfoFourNewFieldsCarryThrough(t *testing.T) {
	info := model.DeviceInfo{
		SN: "L10TEST002", Model: "CS-L10-6K2",
		Phase: "single", InverterModule: "L10-2026-0002", HardwareVersion: "HW-2.1", BootloaderVersion: "BL-1.1",
	}
	infoJSON, err := json.Marshal(info)
	require.NoError(t, err)

	var req internalDeviceInfoRequest
	require.NoError(t, json.Unmarshal(infoJSON, &req))
	require.Equal(t, info.Phase, req.Phase)
	require.Equal(t, info.InverterModule, req.InverterModule)
	require.Equal(t, info.HardwareVersion, req.HardwareVersion)
	require.Equal(t, info.BootloaderVersion, req.BootloaderVersion)
}

// V2.1 单位纪律：rated_power（W 原值）与 rated_power_w（落库列）同源透传。
func TestDeviceInfoRatedPowerWCarryThrough(t *testing.T) {
	payload := `{"sn":"L10TEST003","model":"CS-L10-6K2","rated_power":6000,"rated_power_w":6000,"phase":"single","inverter_module":"M1","hardware_version":"HW1","bootloader_version":"BL1"}`
	var req internalDeviceInfoRequest
	require.NoError(t, json.Unmarshal([]byte(payload), &req))
	require.Equal(t, 6000, req.RatedPowerW)
	require.Equal(t, 6000.0, req.RatedPower)
	require.Equal(t, "single", req.Phase)
}

// 防止未来新增字段破坏契约：比对 struct 字段名集合（仅做静态提示性断言）。
func TestDeviceInfoContractFieldParity(t *testing.T) {
	infoType := reflect.TypeOf(model.DeviceInfo{})
	reqType := reflect.TypeOf(internalDeviceInfoRequest{})
	var infoFields, reqFields []string
	for i := 0; i < infoType.NumField(); i++ {
		infoFields = append(infoFields, infoType.Field(i).Name)
	}
	for i := 0; i < reqType.NumField(); i++ {
		name := reqType.Field(i).Name
		if name == "RetryCount" { // internal 字段无契约
			continue
		}
		if name == "RatedPowerW" { // 落库列专用字段，非 MQTT 主题契约（见键名对齐测试的 rated_power_w）
			continue
		}
		reqFields = append(reqFields, name)
	}
	require.ElementsMatch(t, infoFields, reqFields, "DeviceInfo 与 internalDeviceInfoRequest 字段应一一对应")
}
