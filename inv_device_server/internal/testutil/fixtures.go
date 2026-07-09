package testutil

import (
	"encoding/json"
	"time"

	"inv-device-server/internal/model"
)

// ==================== 设备信息工厂 ====================

// NewTestDeviceInfo 返回带合理默认值的测试设备信息（MQTT 上报格式）
func NewTestDeviceInfo(overrides ...func(*model.DeviceInfo)) *model.DeviceInfo {
	d := &model.DeviceInfo{
		SN:             "TEST_SN_001",
		Model:          "CSI-5000",
		Manufacturer:   "TestMfg",
		FirmwareARM:    "1.0.0",
		FirmwareESP:    "1.0.0",
		FirmwareDSP:    "1.0.0",
		FirmwareBMS:    "1.0.0",
		Type:           "inverter",
		RatedPower:     5000,
		RatedVoltage:   220,
		RatedFreq:      50.0,
		BatteryVoltage: 48.0,
		BatteryType:    "lithium",
		CellCount:      16,
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// ==================== 遥测数据工厂 ====================

// NewTestACData 返回测试用交流输出数据
func NewTestACData(overrides ...func(*model.ACData)) *model.ACData {
	d := &model.ACData{
		Voltage:     220.5,
		Current:     15.9,
		Power:       3500.0,
		Frequency:   50.01,
		LoadPercent: 70.0,
		SN:          "TEST_SN_001",
		ReceivedAt:  time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestBatteryData 返回测试用电池 BMS 数据
func NewTestBatteryData(overrides ...func(*model.BatteryData)) *model.BatteryData {
	d := &model.BatteryData{
		SOC:         85.0,
		SOH:         98.0,
		Voltage:     48.5,
		Current:     12.3,
		ChargeState: "charging",
		SN:          "TEST_SN_001",
		ReceivedAt:  time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestPVData 返回测试用光伏 MPPT 数据
func NewTestPVData(overrides ...func(*model.PVData)) *model.PVData {
	d := &model.PVData{
		PVVoltage: 320.5,
		PVCurrent: 8.5,
		PVPower:   2724.25,
		MPPTState: "tracking",
		SN:        "TEST_SN_001",
		ReceivedAt: time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestSystemStatus 返回测试用系统状态数据
func NewTestSystemStatus(overrides ...func(*model.SystemStatus)) *model.SystemStatus {
	d := &model.SystemStatus{
		State:      "normal",
		FaultCode:  0,
		AlarmCode:  0,
		TempInv:    45.2,
		TempMOS:    52.1,
		Efficiency: 97.5,
		SN:         "TEST_SN_001",
		ReceivedAt: time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestEnergyData 返回测试用能量统计数据
func NewTestEnergyData(overrides ...func(*model.EnergyData)) *model.EnergyData {
	d := &model.EnergyData{
		DailyPV:        25.5,
		TotalPV:        12500.0,
		DailyCharge:    8.2,
		TotalCharge:    4200.0,
		DailyDischarge: 6.5,
		TotalDischarge: 3100.0,
		DailyLoad:      18.3,
		TotalLoad:      9200.0,
		RuntimeHours:   12.5,
		SN:             "TEST_SN_001",
		ReceivedAt:     time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestCellsData 返回测试用电芯数据
func NewTestCellsData(cellCount int) *model.CellsData {
	voltages := make([]float64, cellCount)
	temps := make([]float64, cellCount)
	for i := 0; i < cellCount; i++ {
		voltages[i] = 3.3 + float64(i)*0.01
		temps[i] = 25.0 + float64(i)*0.5
	}
	return &model.CellsData{
		CellCount:        cellCount,
		Voltages:         voltages,
		Temps:            temps,
		ChargeAhTotal:    120.5,
		DischargeAhTotal: 95.3,
		SN:               "TEST_SN_001",
		ReceivedAt:       time.Now(),
	}
}

// NewTestAlarmData 返回测试用告警数据（MQTT 上报格式）
func NewTestAlarmData(overrides ...func(*model.AlarmData)) *model.AlarmData {
	d := &model.AlarmData{
		Code:      1001,
		Level:     "warning",
		Message:   "过压告警",
		Count:     1,
		Alarms:    []model.AlarmItem{{Code: 1001, Level: "warning", Message: "过压告警"}},
		Timestamp: time.Now().Unix(),
		SN:        "TEST_SN_001",
		ReceivedAt: time.Now(),
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// ==================== 命令相关工厂 ====================

// NewTestDeviceCommand 返回测试用设备命令
func NewTestDeviceCommand(sn, cmdType string, params map[string]interface{}) *model.DeviceCommand {
	return &model.DeviceCommand{
		DeviceSN: sn,
		CmdType:  cmdType,
		Params:   params,
		ReqID:    "req_test_001",
	}
}

// NewTestCommandResponse 返回测试用命令响应
func NewTestCommandResponse(sn, cmd string, success bool) *model.CommandResponse {
	return &model.CommandResponse{
		TaskID:    "task_test_001",
		Cmd:       cmd,
		Success:   success,
		Message:   "ok",
		Timestamp: time.Now().Unix(),
		SN:        sn,
		ReceivedAt: time.Now(),
	}
}

// ==================== 在线状态工厂 ====================

// NewTestOnlineStatus 返回测试用在线状态
func NewTestOnlineStatus(online bool) *model.OnlineStatus {
	return &model.OnlineStatus{
		Online: online,
		RSSI:   -65,
		IP:     "192.168.1.100",
	}
}

// ==================== 设备实时聚合工厂 ====================

// NewTestDeviceRealtime 返回测试用设备实时聚合数据
func NewTestDeviceRealtime(sn string) *model.DeviceRealtime {
	return &model.DeviceRealtime{
		DeviceSN:     sn,
		AC:           NewTestACData(),
		Battery:      NewTestBatteryData(),
		PV:           NewTestPVData(),
		SysStatus:    NewTestSystemStatus(),
		Energy:       NewTestEnergyData(),
		OnlineStatus: NewTestOnlineStatus(true),
		UpdatedAt:    time.Now(),
	}
}

// ==================== 数据库设备模型工厂 ====================

// NewTestDBDevice 返回测试用数据库设备记录
func NewTestDBDevice(overrides ...func(*model.Device)) *model.Device {
	now := time.Now()
	d := &model.Device{
		ID:          1,
		SN:          "TEST_SN_001",
		Model:       "CSI-5000",
		RatedPower:  5000.0,
		FirmwareARM: "1.0.0",
		FirmwareESP: "1.0.0",
		FirmwareDSP: "1.0.0",
		FirmwareBMS: "1.0.0",
		Timezone:    "Asia/Shanghai",
		Status:      1,
		IPAddress:   "192.168.1.100",
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestDeviceModel 返回测试用设备型号（数据库模型）
func NewTestDeviceModel(overrides ...func(*model.DeviceModel)) *model.DeviceModel {
	m := &model.DeviceModel{
		ID:           1,
		ModelCode:    "CSI-5000",
		ModelName:    "CSI-5000 5kW 逆变器",
		Manufacturer: "TestMfg",
		Category:     "inverter",
		RatedPowerKW: 5.0,
		Description:  "测试型号",
		IsActive:     true,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	for _, fn := range overrides {
		fn(m)
	}
	return m
}

// NewTestModelMetadata 返回测试用型号元数据（运行时缓存）
func NewTestModelMetadata() *model.ModelMetadata {
	m := NewTestDeviceModel()
	fields := map[string]*model.DeviceModelField{
		"ac_voltage": {
			ID: 1, ModelID: 1, FieldKey: "ac_voltage", FieldName: "交流电压",
			FieldType: "float", Unit: "V", Sort: 1, IsShow: true,
		},
		"ac_power": {
			ID: 2, ModelID: 1, FieldKey: "ac_power", FieldName: "交流功率",
			FieldType: "float", Unit: "W", Sort: 2, IsShow: true,
		},
	}
	fieldOrder := []*model.DeviceModelField{fields["ac_voltage"], fields["ac_power"]}
	return &model.ModelMetadata{
		Model:      m,
		Fields:     fields,
		FieldOrder: fieldOrder,
		Protocols:  nil,
	}
}

// ==================== MQTT 消息工厂 ====================

// NewTestMQTTMessage 构造 MQTT 消息 payload（JSON 格式）
func NewTestMQTTMessage(data interface{}) []byte {
	b, _ := json.Marshal(data)
	return b
}

// NewTestMQTTTopic 构造 MQTT 主题
func NewTestMQTTTopic(sn, topicType string) string {
	return "cs_inv/" + sn + "/" + topicType
}
