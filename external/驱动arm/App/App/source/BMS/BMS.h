

#ifndef _BMS_H
#define _BMS_H
#include "TypeRedefine.h"

#define MAX_BMS_ADDR 15

struct warningFlagBit_t
{
	u8 COV :1;   //单体过压警告
	u8 CUV :1;   //单体欠压警告
	u8 POV :1;   //总过压警告
	u8 PUV :1;   //总欠压警告
	u8 OCC :1;   //充电过流警告
	u8 OCD :1;   //放电过流警告
	u8 RSVD:2;   //
	u8 OTC :1;   //充电过温警告
	u8 OTD :1;   //放电过温警告
	u8 UTC :1;   //充电低温警告
	u8 UTD :1;   //放电低温警告
	u8 EOT :1;   //环境过温警告
	u8 EUT :1;   //环境低温警告
	u8 MOT :1;   //MOS过温警告
	u8 lowSOC :1;//低电量警告
} ;
		
struct statusFaultFlagBit_t
{
	u8 CHG_MOS_FAULT                :1; 
	u8 DSG_MOS_FAULT                :1;
	u8 TEMP_SENSOR_FAULT            :1;
	u8 RSVD	                        :1;
	u8 BAT_CELL_FAULT               :1; 
	u8 FRONT_END_SAMPLING_COMM_FAULT:1;
	u8 RSVD1	                    :2;	
	u8 CHARGING                     :1;
	u8 DISCHARGING                  :1;
	u8 CHG_MOS_ON                   :1;
	u8 DSG_MOS_ON                   :1;
	u8 CHG_LIMITER_ON               :1;
	u8 RSVD2	                    :1;	
	u8 CHG_INVERSED                 :1;
	u8 HEATER_ON                    :1;
};

struct protectionFlagBit_t
{
	u8 COV :1;   //单体过压保护
	u8 CUV :1;   //单体欠压保护
	u8 POV :1;   //总过压保护
	u8 PUV :1;   //总欠压保护
	u8 OCC :1;   //充电过流保护
	u8 OCD :1;   //放电过流保护
	u8 SC  :1;	 //短路保护
	u8 chargerOV :1;//充电器电压保护	
	u8 OTC :1;   //充电过温保护
	u8 OTD :1;   //放电过温保护
	u8 UTC :1;   //充电低温保护
	u8 UTD :1;   //放电低温保护
	u8 MOT :1;   //MOS过温保护
	u8 EOT :1;   //环境过温保护
	u8 EUT :1;   //环境低温保护	
	u8 RSVD :1;  //
} ;
		
#pragma pack(1)
//电池信息关闭充放电mos
typedef struct _battery {
	uint8_t batExist;//通讯成功置1
	uint16_t voltage;//总电压 单位：10mV
	int16_t current;//总电流, 单位：10mA,范围:-328~327A
	uint8_t  SOC;    //SOC    单位：%
	uint8_t  SOH;	//SOH     单位：%
	uint16_t remainCapacity; //剩余容量：mAh
	uint16_t fullCapacity;
	uint16_t designCapacity;//最大支持(2^16-1)*10mAh=655Ah
	uint16_t cycle;
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union
	{
		struct warningFlagBit_t warningFlagBit;
		u16 warningFlag;
	} ;
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{
		struct protectionFlagBit_t protectionFlagBit;
		u16 protectionFlag;
	} ;
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{
		struct statusFaultFlagBit_t statusFaultFlagBit;
		u16 statusFaultFlag;
	} ;
	
	uint16_t balanceStatus;
	uint16_t maxCellVoltage;
	uint16_t minCellVoltage;
	int16_t cellTemp[4];
	int16_t maxCellTemp;
	int16_t minCellTemp;
	int16_t MOSTemp;
	int16_t envTemp;
} battery_t;
#pragma pack()





#pragma pack(1)
//电池信息关闭充放电mos
typedef struct _batterySum {
	u8 batteryCnt;				//电池计数
	uint16_t voltage;			//总电压 单位：10mV
	int32_t current;			//总电流, 单位：10mA,范围:-328~327A
	uint16_t  SOC;    			//SOC    单位：%
	uint16_t  SOH;				//SOH     单位：%
	uint16_t remainCapacity; 	//剩余容量：mAh
	uint16_t fullCapacity;
	uint32_t designCapacity;	//最大支持(2^16-1)*10mAh=655Ah
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{
		struct warningFlagBit_t warningFlagBit;
		u16 warningFlag;
	} ;
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{
		struct protectionFlagBit_t protectionFlagBit;
		u16 protectionFlag;
	} ;
	
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{
		struct statusFaultFlagBit_t statusFaultFlagBit;
		u16 statusFaultFlag;
	} ;
	
	uint16_t balanceStatus;
	uint16_t cellVoltage[16];
	int16_t cellTemp[4];
	uint16_t cycle;
	uint16_t maxCellVoltage;
	uint16_t minCellVoltage;
	int16_t maxCellTemp;
	int16_t minCellTemp;
	int16_t MOSTemp;
	int16_t PCBTemp;
	int16_t envTemp;
	uint8_t  batteryMode;
	uint8_t batteryStatus;
	uint32_t  total_chg_capacity;
	uint32_t  total_dsg_capacity;
	uint16_t  chg_request_cur;
	int16_t  chg_request_volt;
	uint8_t  system_mode;
	
	uint16_t chargingVoltage;//充电电压, modbus地址60

	/* ==== BMS 扩展字段(2026-09, 数据源: 储能BMS PC485协议 pack_info, UsartBms0.c 填充) ==== */
	uint16_t maxCellVoltageIdx;//最高单体电压序号(0起)
	uint16_t minCellVoltageIdx;//最低单体电压序号(0起)
	uint32_t faultStatus;      //BMS fault_status 位图(bit0短路 bit1反接 bit2NTC断线 ...)
	uint64_t alarmStatus;      //BMS alarm_status 位图(每类告警2bit等级, alarmN在bit[2N+1:2N])
} batterySum_t;
#pragma pack()



extern batterySum_t batterySum;
extern battery_t battery[MAX_BMS_ADDR+1];

#endif


