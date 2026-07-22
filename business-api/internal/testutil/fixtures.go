package testutil

import (
	"fmt"
	"time"

	"inv-api-server/internal/model"

	"golang.org/x/crypto/bcrypt"
)

// ==================== 用户工厂 ====================

// NewTestUser 返回带合理默认值的测试用户。
// 密码为 "Test@123456"，已经过 bcrypt 哈希。
func NewTestUser(overrides ...func(*model.User)) *model.User {
	now := time.Now()
	hash, _ := bcrypt.GenerateFromPassword([]byte("Test@123456"), bcrypt.MinCost)
	u := &model.User{
		ID:           1,
		Phone:        "13800138000",
		Email:        "test@example.com",
		PasswordHash: string(hash),
		Nickname:     "测试用户",
		Avatar:       "",
		Role:         5, // 普通用户
		Status:       1, // 正常
		Timezone:     "Asia/Shanghai",
		LastLoginIP:  "127.0.0.1",
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	for _, fn := range overrides {
		fn(u)
	}
	return u
}

// NewTestAdmin 返回管理员用户
func NewTestAdmin() *model.User {
	return NewTestUser(func(u *model.User) {
		u.ID = 100
		u.Role = 1
		u.Nickname = "管理员"
		u.Phone = "13900139000"
		u.Email = "admin@example.com"
	})
}

// ==================== 电站工厂 ====================

// NewTestStation 返回带合理默认值的测试电站
func NewTestStation(overrides ...func(*model.Station)) *model.Station {
	now := time.Now()
	s := &model.Station{
		ID:         1,
		UserID:     1,
		Name:       "测试电站",
		Province:   "浙江省",
		City:       "杭州市",
		District:   "西湖区",
		Address:    "测试路1号",
		Capacity:   10.0,
		PanelCount: 20,
		Latitude:   30.27,
		Longitude:  120.15,
		Timezone:   "Asia/Shanghai",
		Status:     1,
		CreatedAt:  now,
		UpdatedAt:  now,
	}
	for _, fn := range overrides {
		fn(s)
	}
	return s
}

// ==================== 设备工厂 ====================

// NewTestDevice 返回带合理默认值的测试设备
func NewTestDevice(overrides ...func(*model.Device)) *model.Device {
	now := time.Now()
	d := &model.Device{
		ID:             1,
		SN:             "TEST_SN_001",
		Model:          "CSI-5000",
		Manufacturer:   "TestMfg",
		FirmwareArm:    "1.0.0",
		FirmwareEsp:    "1.0.0",
		FirmwareDSP:    "1.0.0",
		FirmwareBMS:    "1.0.0",
		MainVersion:    "1.0.0",
		DeviceType:     "inverter",
		RatedPower:     5000.0,
		RatedVoltage:   220.0,
		RatedFreq:      50.0,
		BatteryVoltage: 48.0,
		BatteryType:    "lithium",
		CellCount:      16,
		UserID:         1,
		Timezone:       "Asia/Shanghai",
		Status:         1,
		CurrentPower:   3500.0,
		DailyEnergy:    25.5,
		LastOnlineAt:   &now,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	for _, fn := range overrides {
		fn(d)
	}
	return d
}

// NewTestDeviceWithSN 返回指定 SN 的测试设备
func NewTestDeviceWithSN(sn string) *model.Device {
	return NewTestDevice(func(d *model.Device) {
		d.SN = sn
	})
}

// ==================== 告警工厂 ====================

// NewTestAlarm 返回带合理默认值的测试告警
func NewTestAlarm(overrides ...func(*model.Alarm)) *model.Alarm {
	now := time.Now()
	a := &model.Alarm{
		ID:           1,
		DeviceSN:     "TEST_SN_001",
		UserID:       1,
		AlarmLevel:   2,
		FaultCode:    "E001",
		FaultMessage: "过压告警",
		FaultDetail:  "电网电压超过上限",
		Status:       0, // 未处理
		OccurredAt:   now,
		CreatedAt:    now,
	}
	for _, fn := range overrides {
		fn(a)
	}
	return a
}

// ==================== 设备型号工厂 ====================

// NewTestDeviceModel 返回带合理默认值的测试设备型号
func NewTestDeviceModel(overrides ...func(*model.DeviceModel)) *model.DeviceModel {
	m := &model.DeviceModel{
		ID:           1,
		ModelCode:    "CSI-5000",
		ModelName:    "CSI-5000 5kW 逆变器",
		Manufacturer: "TestMfg",
		Category:     "inverter",
		RatedPowerKw: 5.0,
		Description:  "测试型号",
		IsActive:     true,
		DeviceCount:  0,
		CreatedAt:    time.Now().Format("2006-01-02 15:04:05"),
		UpdatedAt:    time.Now().Format("2006-01-02 15:04:05"),
	}
	for _, fn := range overrides {
		fn(m)
	}
	return m
}

// NewTestDeviceModelField 返回测试型号字段
func NewTestDeviceModelField(overrides ...func(*model.DeviceModelField)) *model.DeviceModelField {
	f := &model.DeviceModelField{
		ID:        1,
		ModelID:   1,
		FieldKey:  "ac_voltage",
		FieldName: "交流电压",
		FieldType: "float",
		Unit:      "V",
		Sort:      1,
		IsShow:    true,
		IsControl: false,
		GroupName: "ac_output",
	}
	for _, fn := range overrides {
		fn(f)
	}
	return f
}

// NewTestDeviceModelProtocol 返回测试型号协议配置
func NewTestDeviceModelProtocol(overrides ...func(*model.DeviceModelProtocol)) *model.DeviceModelProtocol {
	p := &model.DeviceModelProtocol{
		ID:           1,
		ModelID:      1,
		TopicPattern: "cs_inv/+/data/*",
		ParseType:    "json",
		IsActive:     true,
		CreatedAt:    time.Now().Format("2006-01-02 15:04:05"),
	}
	for _, fn := range overrides {
		fn(p)
	}
	return p
}

// ==================== 固件工厂 ====================

// NewTestFirmware 返回带合理默认值的测试固件
func NewTestFirmware(overrides ...func(*model.Firmware)) *model.Firmware {
	f := &model.Firmware{
		ID:         1,
		Model:      "CSI-5000",
		Version:    "2.0.0",
		FileURL:    "https://example.com/firmware/v2.0.0.bin",
		FileSize:   1048576,
		FileMD5:    "d41d8cd98f00b204e9800998ecf8427e",
		FileSHA256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		Changelog:  "修复若干问题",
		IsForce:    false,
		UploadedBy: 100,
		Status:     1,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
		TargetChip: "arm",
		MainVersion: "2.0.0",
	}
	for _, fn := range overrides {
		fn(f)
	}
	return f
}

// ==================== 升级任务工厂 ====================

// NewTestUpgradeTask 返回带合理默认值的测试升级任务
func NewTestUpgradeTask(overrides ...func(*model.UpgradeTask)) *model.UpgradeTask {
	now := time.Now()
	fwID := int64(1)
	ut := &model.UpgradeTask{
		ID:             1,
		Name:           "测试升级任务",
		TaskType:       model.TaskTypeSingle,
		FirmwareID:     &fwID,
		Model:          "CSI-5000",
		TargetVersion:  "2.0.0",
		Status:         model.TaskStatusDraft,
		ExecuteMode:    model.ExecuteModeImmediate,
		RolloutPercent: 100,
		TotalDevices:   10,
		Source:         model.OTASourceAdmin,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	for _, fn := range overrides {
		fn(ut)
	}
	return ut
}

// ==================== 设备升级工厂 ====================

// NewTestDeviceUpgrade 返回带合理默认值的测试设备升级记录
func NewTestDeviceUpgrade(overrides ...func(*model.DeviceUpgrade)) *model.DeviceUpgrade {
	now := time.Now()
	pushedBy := int64(100)
	du := &model.DeviceUpgrade{
		ID:              1,
		DeviceSN:        "TEST_SN_001",
		FirmwareID:      1,
		FirmwareVersion: "2.0.0",
		TargetChip:      "arm",
		OldVersion:      "1.0.0",
		Status:          model.UpgradeStatusPending,
		Progress:        0,
		PushedBy:        &pushedBy,
		Source:          model.OTASourceAdmin,
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	for _, fn := range overrides {
		fn(du)
	}
	return du
}

// ==================== 升级包工厂 ====================

// NewTestUpgradePackage 返回带合理默认值的测试升级包
func NewTestUpgradePackage(overrides ...func(*model.UpgradePackage)) *model.UpgradePackage {
	now := time.Now()
	pkg := &model.UpgradePackage{
		ID:             1,
		Model:          "CSI-5000",
		MainVersion:    "2.0.0",
		Changelog:      "组合升级包",
		UserVersion:    "2.0.0",
		UserChangelog:  "系统升级",
		RolloutType:    model.RolloutTypeAll,
		RolloutTargets: "",
		IsPublished:    false,
		IsForce:        false,
		Status:         0,
		CreatedBy:      100,
		CreatedAt:      now,
		UpdatedAt:      now,
	}
	for _, fn := range overrides {
		fn(pkg)
	}
	return pkg
}

// NewTestUpgradePackageItem 返回测试升级包明细
func NewTestUpgradePackageItem(packageID, firmwareID int64, chip string) *model.UpgradePackageItem {
	return &model.UpgradePackageItem{
		ID:              1,
		PackageID:       packageID,
		FirmwareID:      firmwareID,
		TargetChip:      chip,
		FirmwareVersion: "2.0.0",
		FileURL:         fmt.Sprintf("https://example.com/firmware/%s_v2.0.0.bin", chip),
		FileSize:        1048576,
		FileMD5:         "d41d8cd98f00b204e9800998ecf8427e",
		FileSHA256:      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
}

// ==================== 实时数据工厂 ====================

// NewTestRealtimeData 返回测试用设备实时数据
func NewTestRealtimeData(sn string) *model.DeviceRealtimeData {
	return &model.DeviceRealtimeData{
		DeviceSN:             sn,
		DataTime:             time.Now(),
		Online:               true,
		Manufacturer:         "TestMfg",
		Model:                "CSI-5000",
		TotalActivePower:     3500.0,
		TotalReactivePower:   100.0,
		TotalApparentPower:   3501.4,
		PowerFactor:          0.99,
		GridFrequency:        50.01,
		PhaseAVoltage:        220.5,
		PhaseACurrent:        15.9,
		InternalTemperature:  45.2,
		DailyPowerYields:     25.5,
		TotalPowerYields:     12500.0,
		MPPTVoltage:          []float64{320.5, 318.2},
		MPPTCurrent:          []float64{8.5, 8.3},
		TotalDCPower:         5400.0,
		WorkState1:           "normal",
		WorkState1Code:       0,
		ActivePowerSetting:   100.0,
		ReactivePowerSetting: 0.0,
		PowerFactorSetting:   1.0,
	}
}

// ==================== 操作日志工厂 ====================

// NewTestAuditLog 返回测试用操作日志
func NewTestAuditLog(userID int64, action, resourceType string) *model.AuditLog {
	return &model.AuditLog{
		ID:              1,
		UserID:          userID,
		OperationType:   action,
		OperationDetail: fmt.Sprintf("执行 %s 操作", action),
		Result:          "success",
		IPAddress:       "127.0.0.1",
		CreatedAt:       time.Now(),
	}
}
