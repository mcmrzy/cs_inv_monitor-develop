package handler

import "testing"

func TestAlarmV1PushCopy(t *testing.T) {
	cases := []struct {
		name           string
		sn             string
		data           alarmV1Data
		wantNotifyType string
		wantTitle      string
		wantContent    string
		wantLevel      int
	}{
		{
			name:           "3KU 母线软启故障",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 0, Code: 0x5600, Level: 2, State: 1},
			wantNotifyType: "device_alarm", wantTitle: "设备告警",
			wantContent: "设备 SN1000000000001: 母线软启故障", wantLevel: 3,
		},
		{
			name:           "3KU 恢复",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 0, Code: 0x5600, Level: 2, State: 0},
			wantNotifyType: "alarm_cleared", wantTitle: "故障已恢复",
			wantContent: "设备 SN1000000000001 母线软启故障 已恢复", wantLevel: 0,
		},
		{
			name:           "V1.27 的同一物理位",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 0, Code: 0x4600, Level: 2, State: 1},
			wantNotifyType: "device_alarm", wantTitle: "设备告警",
			wantContent: "设备 SN1000000000001: 市电软启失败", wantLevel: 3,
		},
		{
			name:           "严重告警已知码",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 1, Code: 1, Level: 2, State: 1},
			wantNotifyType: "device_alarm",
			wantTitle:      "设备告警",
			wantContent:    "设备 SN1000000000001: 逆变器过温保护",
			wantLevel:      3,
		},
		{
			name:           "警告级告警已知码",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 0, Code: 7, Level: 1, State: 1},
			wantNotifyType: "device_alarm",
			wantTitle:      "设备告警",
			wantContent:    "设备 SN1000000000001: 电池SOC过低",
			wantLevel:      2,
		},
		{
			name:           "通讯板电池低压 18434",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 0, Code: 18434, Level: 1, State: 1},
			wantNotifyType: "device_alarm", wantTitle: "设备告警",
			wantContent: "设备 SN1000000000001: 电池低压", wantLevel: 2,
		},
		{
			name:           "通讯板逆变器通信中断 18944",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 2, Code: 18944, Level: 2, State: 1},
			wantNotifyType: "device_alarm", wantTitle: "设备告警",
			wantContent: "设备 SN1000000000001: 逆变器通信中断", wantLevel: 3,
		},
		{
			name:           "未知告警码回退",
			sn:             "SN1000000000002",
			data:           alarmV1Data{Source: 2, Code: 99, Level: 2, State: 1},
			wantNotifyType: "device_alarm",
			wantTitle:      "设备告警",
			wantContent:    "设备 SN1000000000002: 未知告警(代码 99)",
			wantLevel:      3,
		},
		{
			name:           "恢复已知码",
			sn:             "SN1000000000001",
			data:           alarmV1Data{Source: 1, Code: 3, Level: 2, State: 0},
			wantNotifyType: "alarm_cleared",
			wantTitle:      "故障已恢复",
			wantContent:    "设备 SN1000000000001 电池欠压保护 已恢复",
			wantLevel:      0,
		},
		{
			name:           "legacy 整机恢复码0",
			sn:             "SN1000000000003",
			data:           alarmV1Data{Source: 0, Code: 0, Level: 1, State: 0},
			wantNotifyType: "alarm_cleared",
			wantTitle:      "故障已恢复",
			wantContent:    "设备 SN1000000000003 故障 已恢复",
			wantLevel:      0,
		},
		{
			name:           "恢复未知码回退",
			sn:             "SN1000000000003",
			data:           alarmV1Data{Source: 0, Code: 55, Level: 1, State: 0},
			wantNotifyType: "alarm_cleared",
			wantTitle:      "故障已恢复",
			wantContent:    "设备 SN1000000000003 故障 已恢复",
			wantLevel:      0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			notifyType, title, content, alarmLevel := alarmV1PushCopy(tc.sn, tc.data)
			if notifyType != tc.wantNotifyType {
				t.Errorf("notifyType = %q, want %q", notifyType, tc.wantNotifyType)
			}
			if title != tc.wantTitle {
				t.Errorf("title = %q, want %q", title, tc.wantTitle)
			}
			if content != tc.wantContent {
				t.Errorf("content = %q, want %q", content, tc.wantContent)
			}
			if alarmLevel != tc.wantLevel {
				t.Errorf("alarmLevel = %d, want %d", alarmLevel, tc.wantLevel)
			}
		})
	}
}
