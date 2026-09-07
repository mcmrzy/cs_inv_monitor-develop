
#ifndef __CollectorParamAddr_H
#define __CollectorParamAddr_H

#include "TypeRedefine.h"

#define Index_OutputPriority         0x0000  //输出优先级
#define Index_MaxChargeCurrentAll    0x0001  //最大充电电流（市电+太阳能）
#define Index_ACInVoltRange          0x0002  //交流输入电压范围
#define Index_BatCapacity            0x0003  //电池容量
#define Index_BatteryType            0x0004  //电池类型
#define Index_OverloadRestart        0x0005  //过载自动重启
#define Index_HighTemperatureRestart 0x0006  //温度过高自动重启
#define Index_OutputVoltage          0x0007  //输出电压
#define Index_OutputFrequency        0x0008  //输出频率
#define Index_Master_Slave           0x0009  //主、从机模式
#define Index_MaxChargeCityCurrent   0x000A  //最大市电充电电流
#define Index_LowVoltReturnCityPower 0x000B  //电池低压点设置回市电模式
#define Index_HighVoltReturnBattery  0x000C  //电池高压点设置回电池模式
#define Index_BatteryChargePriority  0x000D  //电池充电优先级
#define Index_AlarmControl           0x000E  //报警控制
#define Index_BackLightCtrl          0x000F  //背光控制
#define Index_PowerShutdownAlarm     0x0010  //主电源中断报警
#define Index_OverloadUseCityPower   0x0011  //过载启用市电模式
#define Index_ParaMaxDisChgCurr      0x0012  //并机系统最大放电电流
#define Index_ParaMaxChgCurr         0x0013  //并机系统最大充电电流
#define Index_RecoverThresholdVolt	 0x0014  //恢复输出阈值电压
#define Index_SolarPowerBalance      0x0015  //太阳能发电平衡模式
#define Index_ACOutputMode           0x0016  //交流电输出模式  
#define Index_LiBatMaterial          0x0017  //锂电池材料类型
#define Index_CellInSerial_LiFePO4   0x0018  //磷酸铁锂电池串数
#define Index_CellInSerial_Li_NMC    0x0019  //三元电池串数
#define Index_EqEnable               0x001A  //均衡设置
#define Index_EqVoltageSet           0x001B  //均衡电压设置
#define Index_EqTimeSet              0x001C  //均衡时间设置
#define Index_EqtTimeoutSet          0x001D  //均衡超时设置
#define Index_EqtIntervalSet         0x001E  //均衡间隔设置
#define Index_EqactivateSet          0x001F  //均衡激活开关
#define Index_ChargeTimeSet          0x0020  //充电时间设置
#define Index_CloseChargeTimeSet     0x0021  //关闭充电时间设置
#define Index_LVoltOpenGenerator     0x0022  //电池低压点设置开发电机
#define Index_HVoltCloseGenerator    0x0023  //电池高压点设置关发电机
#define Index_SocBackUtl             0x0024  //电池低电量切回市电
#define Index_SocBackBat             0x0025  //电池高电量切回电池
#define Index_SocBackGen             0x0026  //电池低电量开发电机
#define Index_SocCloseGen            0x0027  //电池高电量关发电机
#define Index_Soccutoff              0x0028  //电池低电量保护点
#define Index_BuzzerEN               0x0029  //蜂鸣器使能开关
#define Index_S_GradeSOC	         0x002A  //S_短时强制手动开启限制SOC
#define Index_A_GradeSOC	         0x002B  //A级开关开启SOC
#define Index_B_GradeSOC	         0x002C  //B级开关开启SOC
#define Index_ManualSocket	         0x002D  //手动控制从机
#define Index_ControlSocket	         0x002E  //开关手动控制模式的从机
#define Index_RecoverThresholdSoc	 0x002F  //恢复输出阈值电量
#define Index_LiBatProtocolType      0x0030  //电池协议类型
#define Index_GenRateWatt	         0x0031	 //发电机额定功率
#define Index_GeBalanceEn            0x0032  //发电机平衡使能
#define Index_GenWorkStartTime1L	 0x0033	//发电机输出开始时间策略1
#define Index_GenWorkStartTime1H	 0x0034	//发电机输出开始时间策略1
#define Index_GenWorkEndTime1L	     0x0035	//发电机输出结束时间策略1
#define Index_GenWorkEndTime1H	     0x0036	//发电机输出结束时间策略1
#define Index_GenWorkStartTime2L	 0x0037	//发电机输出开始时间策略2
#define Index_GenWorkStartTime2H	 0x0038	//发电机输出开始时间策略2
#define Index_GenWorkEndTime2L	     0x0039	//发电机输出结束时间策略2
#define Index_GenWorkEndTime2H	     0x003A	//发电机输出结束时间策略2
#define Index_UtiOutputStartTime1L	 0x003B	//市电输出开始时间策略1
#define Index_UtiOutputStartTime1H	 0x003C	//市电输出开始时间策略1
#define Index_UtiOutputEndTime1L	 0x003D //市电输出结束时间策略1
#define Index_UtiOutputEndTime1H	 0x003E	//市电输出结束时间策略1
#define Index_UtiOutputStartTime2L	 0x003F	//市电输出开始时间策略2
#define Index_UtiOutputStartTime2H	 0x0040	//市电输出开始时间策略2
#define Index_UtiOutputEndTime2L	 0x0041	//市电输出结束时间策略2
#define Index_UtiOutputEndTime2H	 0x0042	//市电输出结束时间策略2
#define Index_VbatAgm            		0x0043  //AGM铅电池均充电压
#define Index_VbatFlood          0x0044  //flooded铅电池均充电压
#define Index_VbatUserPb         0x0045  //UserDef-Pb电池均充电压
#define Index_VbatAgmFloat           0x0046  //AMG铅电池浮充电压
#define Index_VbatFloodFloat         0x0047  //flood铅电池浮充电压
#define Index_VbatLiFloat            0x0048  //Lithium池电池浮充电压
#define Index_VbatUserPbFloat        0x0049  //UserDef-Pb电池浮充电压
#define Index_VbatUserLiFeFloat      0x004A  //UserDef-Li:LiFePO4电池浮充电压
#define Index_VbatUserLiNmcFloat     0x004B  //UserDef-Li:Li-NMC电池浮充电压
#define Index_VbatAgmCutOff          0x004C  //AMG铅电池保护电压
#define Index_VbatFloodCutOff        0x004D  //flooded铅电池保护电压
#define Index_VbatLiCutOff           0x004E  //Lithium电池保护电压
#define Index_VbatUserPbCutOff       0x004F  //UserDef-Pb电池保护电压
#define Index_VbatUserLiFeCutOff     0x0050  //UserDef-Li:LiFePO4电池保护电压
#define Index_VbatUserLiNmcCutOff    0x0051  //UserDef-Li:Li-NMC电池保护电压
#define Index_SocMaxUtlChg	         0x0052  //市电充电截止SOC
#define Index_VMaxUtlChg	         0x0053  //市电充电截止电压

#define ConfigParamMaxIndex    (Index_VMaxUtlChg+1)



#define RunParamStartIndex 0x03E8
/* RunParamEndIndex 定义移至 RunParamDef 之后, 由结构体实际大小自动推导(新增字段免维护) */
#pragma pack(1)
typedef struct
{
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{//bit0: Standby; bit1: Fault;bit2: Charge;bit3: Discharge;bit4: PvCharge; bit5: AcCharge;bit6: GeCharge;bit7: AC Bypass;
     //bit8:ToLoad;bit9:Pvinput,bit10:AcInput;bit11:GeInput;
		struct {
		u16 StandBy     :1, //待机状态
			Fault       :1, //出错   
            Charge      :1, //充电         
			Discharging :1, //放电中
			PVCharging  :1, //PV充电
			ACCharging  :1, //AC充电
			GenCharging :1, //发电机充电
			ACBypass    :1, //AC 旁路
            ToLoad      :1, //负载
            Pvinput     :1,
            AcInput     :1,
            GeInput     :1,
			rsvd        :4;
		} SysStatusBits;
		u16 SysStatus;//系统状态
	 };
	
    u16 Vpv1; //光伏1电压	0.1V
    u16 Vpv2; //光伏2电压	0.1V
//    u32 Ppv1; //光伏1充电功率	0.1W
//    u32 Ppv2; //光伏2充电功率	0.1W
    u32 Ppv; //光伏2充电功率	0.1W	 
    u16 Buck1Curr; //Buck1 current	0.1A
    u16 Buck2Curr; //Buck2 current	0.1A
    u16 BoostTemp; //Boost Temperature	0.1C
    u16 InvertTemp; //Invert Temperature	0.1C
    u32 OutputWatt; //输出有功功率，指负载	0.1W		
    u32 OutputVA; //输出视在功率，指负载	0.1VA		
    u16 OutputCurr; //输出电流，指负载	0.1A
    u32 ACChrWatt; //交流充电功率	0.1W		
    u32 ACChrVA; //交流充电视在功率	0.1VA		
    u16 GridVolt; //交流输入电压	0.1V
    u16 GridFreq; //交流输入频率	0.01Hz
    u16 ACOutputVolt; //交流输出电压	0.1V
    u16 ACOutputFreq; //交流输出频率	0.01Hz
    u32 ACInWatt; //交流输入功率	0.1W		0.1W
    u32 ACInVA; //交流输入视在功率	0.1VA		
    u32 ACDisChrWatt; //交流旁路放电功率	0.1kWh		
    u32 ACDisChrVA; //交流旁路放电视在功率	0.1VA		
    u16 ACChrCurr; //交流为电池充电电流	0.1A
    u16 BatVolt; //电池电压	0.01V
    u16 BatterySOC; //电池电量	1%
    u32 BatDisChrWatt; //电池放电功率	0.1W		
    u32 BatChrWatt; //电池充电功率	0.1W		
    u16 BatChgCurr; //电池充电电流	0.1A
    u16 BatDischgCurr; //电池放电电流	0.1A
    u16 BatOverCharge; //电池过充标志	
    u16 BusVolt; //总线电压	0.01V
    u16 PvTemp; //逆变桥温度	0.1C
    u16 InvCurr; //逆变桥电流	0.1A
    u16 TransformerTemp; //变压器温度	0.1C
    u16 LoadPercent; //负载百分比	0.10%
    u16 ParaChgCurr; //并网系统总充电电流	1A
    u32 WorkTimeTotal; //逆变器工作总时长	1s		
    u16 MpptFanSpeed; //MPPT风扇转速	1%
    u16 InvFanSpeed; //逆变风扇转速	1%
    u16 PairedSocket;//已配对从机
    u16 OnlineSocket;//在线从机
    u16 OnSocket;	 //从机开关状态
    u64 Warning; //告警位			
    u16 BmsWarning; //BMS告警信息	
    u32 FaultValue; //故障码	
    u32 EGen_today; //发电机今日发电量	0.1kWh		
    u32 EGen_total; //发电机全部发电量	0.1kWh				
    u32 Epv_today; //PV1今日发电量	0.1kWh		
    u32 Epv_total; //PV1全部发电量	0.1kWh		
//    u32 Epv2_today; //PV2今日发电量	0.1kWh		
//    u32 Epv2_total; //PV2全部发电量	0.1kWh		
    u32 Eac_chrToday; //交流今日充电量	0.1kWh		
    u32 Eac_chrTotal; //交流全部充电量	0.1kWh		
    u32 Ebat_dischrToday; //电池今日放电量	0.1kWh		
    u32 Ebat_dischrTotal; //电池全部放电量	0.1kWh		
    u32 Ebat_chrToday; //电池今日充电量	0.1kWh		
    u32 Ebat_chrTotal; //电池全部充电量	0.1kWh		
    u32 Eac_dischrToday; //交流旁路今日放电量	0.1kWh		
    u32 Eac_dischrTotal; //交流旁路全部放电量	0.1kWh		
    u32 Eop_dischrToday; //输出今日放电量	0.1kWh
    u32 Eop_dischrTotal; //输出全部放电量	0.1kWh

    /* ================== BMS 扩展组(2026-09) ==================
     * 数据源: batterySum1(储能BMS PC485协议, UsartBms0.c 填充, ReceiveNewFlag 有效)
     * 起始地址 = 0x03E8 + 原结构体88字 = 0x0440
     * 无效值约定: 无符号量=0xFFFF, 有符号温度=-1000; BmsOnline=0 时整组无效 */
    u16 BmsOnline;         //电池在线 1=收到BMS有效数据
    u16 BmsSoc;            //BMS真实SOC 0.1%(区别于DSP估算的BatterySOC)
    u16 BmsSoh;            //SOH 0.1%
    u16 BmsRemainCap;      //剩余容量 0.1Ah
    u16 BmsFullCap;        //满充容量 0.1Ah
    u16 BmsDesignCap;      //额定容量 0.1Ah
    u16 BmsCycleCnt;       //循环次数
    u16 BmsCellVoltMax;    //最高单体电压 mV
    u16 BmsCellVoltMin;    //最低单体电压 mV
    u16 BmsCellVoltDiff;   //单体压差 mV
    u16 BmsCellVoltMaxIdx; //最高单体序号 0起
    u16 BmsCellVoltMinIdx; //最低单体序号 0起
    s16 BmsCellTempMax;    //电芯温度上限 ℃
    s16 BmsCellTempMin;    //电芯温度下限 ℃
    s16 BmsMosTemp;        //MOS温度 ℃
    s16 BmsEnvTemp;        //环境温度 ℃
    s16 BmsPcbTemp;        //PCB温度 ℃
    u16 BmsBatteryMode;    //0静置/1充电/2放电/3初始化/4回充
    u16 BmsMOSStatus;      //MOS状态 bit0充MOS bit1放MOS bit2预放 bit3预充
    u16 BmsSystemMode;     //BMS系统状态机编号
    u16 BmsChgRequestCur;  //请求充电电流 0.1A
    u16 BmsChgRequestVolt; //请求充电电压 0.1V
    u16 BmsFaultStatusL;   //故障位图 bit0~15(bit0短路 bit1反接 bit2NTC断线...)
    u16 BmsFaultStatusH;   //故障位图 bit16~31
    u16 BmsAlarmW0;        //告警0~7等级(每类2bit: 0单体过压 1总压过高 2充电过流 3充电高温 4充电低温 5单体欠压 6总压过低 7放电过流)
    u16 BmsAlarmW1;        //告警8~15等级(8放电高温 9放电低温 10SOC过低 11~16环境/PCB/MOS温度 17压差 18温差...)
    u16 BmsAlarmW2;        //告警16~19等级
    u32 BmsTotalChgCap;    //累计充电容量 Ah
    u32 BmsTotalDsgCap;    //累计放电容量 Ah
    u16 BmsCellVolt[16];   //16芯电压 mV (bit15=均衡标志, 值取bit12-0)
}RunParamDef;
#pragma pack()

#define RunParamEndIndex   ((RunParamStartIndex) + (sizeof(RunParamDef) >> 1) - 1)


////////可读可写数据/////////////////////////////////////////////////////
#define Index_CtrlParamAlterTimeL     0x00C8 //200
#define Index_CtrlParamAlterTimeH     0x00C9 //201
#define Index_UTCL     0x00CA //202
#define Index_UTCH     0x00CB //203

#define CanReadWriteDataMaxIndex ((Index_UTCH<<1)+2)

#define ReadWiteDataStartIndex 0x00C8
#define ReadWiteDataEndIndex   0x00C9

#pragma pack(1)
typedef struct
{
    u32 CtrlParamAlterTime;

}ReadWiteData_Def;
#pragma pack()



////////只读数据///////////////////////////////////////////////////
#define Index_ARMFwVs      0x190 //400
#define Index_DSPFwVs      0x191
#define Index_InvModuleL   0x192
#define Index_InvModuleH   0x193
#define Index_HwVs         0x194
#define Index_InvSN1       0x195
#define Index_InvSN2       0x197
#define Index_InvSN3       0x199
#define Index_InvSN4       0x19B
#define Index_DevTypeCodeL 0x19D
#define Index_DevTypeCodeH 0x19E
#define Index_RateWatt     0x19F
#define Index_RateVA       0x1A0
#define Index_NomGridVolt  0x1A1
#define Index_NomGridFreq  0x1A2
#define Index_NomBatVolt   0x1A3
#define Index_NomPvCurr    0x1A4
#define Index_NomAcChgCurr 0x1A5
#define Index_NomOpVolt    0x1A6
#define Index_NomOpFreq    0x1A7
#define Index_NomOpPow     0x1A8
#define Index_BLVersion    0x1A9

#define OnlyReadDataMaxIndex ((Index_BLVersion<<1)+2)


#define OnlyReadDataStartIndex 0x190
#define OnlyReadDataEndIndex   0x1A9

#pragma pack(1)
typedef struct
{
    u16 ARMFirmwareVersion;
    u16 DSPFirmwareVersion;
    u16 InverterModuleL;
    u16 InverterModuleH;
    u16 HardwareVersion;
    u32 Inverter_SN1;
    u32 Inverter_SN2;
    u32 Inverter_SN3;
    u32 Inverter_SN4;
    u16 DeviceTypeCodeL;
    u16 DeviceTypeCodeH;
    u16 RateWatt;
    u16 RateVA;
    u16 NomGridVolt;
    u16 NomGridFreq;
    u16 NomBatVolt;
    u16 NomPvCurr;
    u16 NomAcChgCurr;
    u16 NomOpVolt;
    u16 NomOpFreq;
    u16 NomOpPow;
    u16 BLVersion;
}OnlyReadData_Def;
#pragma pack()


#pragma pack(1)
typedef struct
{
//	#pragma anon_unions
	#if defined ( __CC_ARM )
        #pragma anon_unions
    #endif
	union 
	{//bit0: Standby; bit1: Fault;bit2: Charge;bit3: Discharge;bit4: PvCharge; bit5: AcCharge;bit6: GeCharge;bit7: AC Bypass;
     //bit8:ToLoad;bit9:Pvinput,bit10:AcInput;bit11:GeInput;
		struct {
		u16 StandBy     :1, //待机状态
			Fault       :1, //出错   
            Charge      :1, //充电         
			Discharging :1, //放电中
			PVCharging  :1, //PV充电
			ACCharging  :1, //AC充电
			GenCharging :1, //发电机充电
			ACBypass    :1, //AC 旁路
            ToLoad      :1, //负载
            Pvinput     :1,
            AcInput     :1,
            GeInput     :1,
			rsvd        :4;
		} SysStatusBits;
		u16 SysStatus;//系统状态
	};	
	u16 Vpv1; //光伏1电压	1V
	u16 Vpv2; //光伏1电压	1V	
//	u32 Ppv1; //光伏1充电功率	1W
//	u32 Ppv2; //光伏1充电功率	1W
	u32 Ppv;  //光伏1充电功率	1W	
	u32 OutputWatt; //输出有功功率，指负载	0.1W		
	u32 OutputVA; //输出视在功率，指负载	0.1VA		
	u16 OutputCurr; //输出电流，指负载	0.1A
	u32 ACChrWatt; //交流充电功率	0.1W		
	u32 ACChrVA; //交流充电视在功率	0.1VA		
	u16 GridVolt; //交流输入电压	0.1V
	u16 GridFreq; //交流输入频率	0.01Hz
	u16 ACOutputVolt; //交流输出电压	0.1V
	u16 ACOutputFreq; //交流输出频率	0.01Hz
	u32 ACInWatt; //交流输入功率	0.1W		0.1W
	u32 ACInVA; //交流输入视在功率	0.1VA		
	u32 ACDisChrWatt; //交流旁路放电功率	0.1kWh		
	u32 ACDisChrVA; //交流旁路放电视在功率	0.1VA		
	u16 ACChrCurr; //交流为电池充电电流	0.1A
	u16 BatVolt; //电池电压	0.01V
	u16 BatterySOC; //电池电量	1%
	u32 BatDisChrWatt; //电池放电功率	0.1W		
	u32 BatChrWatt; //电池充电功率	0.1W		
	u16 BatChgCurr; //电池充电电流	0.1A
	u16 BatDischgCurr; //电池放电电流	0.1A
	u16 BatOverCharge; //电池过充标志	
	u16 BusVolt; //总线电压	0.01V	
	u16 LoadPercent; //负载百分比	0.10%
	u32 Warning; //告警位			
	u16 BmsWarning; //BMS告警信息	
	u16 FaultValue; //故障码	
	u16 InvertTemp; //逆变电路温度
	u16 BoostTemp; //升压电路温度
	u16 TransformerTemp; //变压器温度
	u16 PVTemp; //光伏电路温度
}TestRunParamDef;
#pragma pack()


#endif





