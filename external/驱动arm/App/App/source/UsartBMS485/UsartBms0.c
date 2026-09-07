
#include "USARTBMS0.h"
#include "_string.h"
#include "BMS.h"
#include "gd32f10x_it.h"
#include "CRC16Modbus.h"
#include "SystemManage.h"
#include "USERFLASH.h"

#define BBJ_BMS_PROTOCOL 5

battery_t battery1[MAX_BMS_ADDR1+1];
batterySum_t batterySum1;			//所有电池的合并信息,电压取第一个电池的电压, 电流求和

u16 sCellVoltageB1[16];		//单包电芯电压暂存
static u16 sChargingVoltageB1;		//BMS请求充电电压暂存
u8 ReceiveNewFlag = 0;

//void LiBMSDecideChgCurrVolt1(void);

void Usart0BMSTransmit1() 
{
	u16 crc;
	
	u8 BMSCmd00[] = {0x7c, 0x78, 0x24, 0x80, 0x01, 0x00, 0x00};	

		crc = modbus_crc16_v2(&BMSCmd00[3], sizeof(BMSCmd00)-3);
		BMSCmd00[1] = crc;
		BMSCmd00[2] = crc>>8;
		USART_SendDataPackage(USART0, BMSCmd00, sizeof(BMSCmd00));

}

u8 ProcessAllBattData1();

u8 RcvBMSPacket1() 
{
	u8 *p = USART0_RxBuff+7;
	u16 rxLen = USART0_RxLength;
	u8 cellNum, tempNum;
	u16 i, rawVal, cellV;
	u16 cellMax = 0, cellMin = 0xFFFF;
	u16 cellMaxIdx = 0, cellMinIdx = 0, balBits = 0;
//	int16_t tempMax = -1000, tempMin = 1000;
	u8 tempType;
	int16_t cellMaxT = -1000, cellMinT = 1000;

	if(rxLen < 6) return 1;

	//--- 电芯电压 ---
	if(USART0_RxBuff[0] == 0x7c && calculate_CRCmodbus16(USART0_RxBuff + 3, USART0_RxLength-3) == ((USART0_RxBuff[2]<<8&0xff00) | USART0_RxBuff[1]))
	{
		
		cellNum = p[0];
		batterySum1.batteryCnt = cellNum;
		p += 1;

		for(i = 0; i < cellNum && i < 16; i++){
			rawVal = (p[1] << 8) | p[0];
			p += 2;

			cellV = (rawVal & 0x1FFF);			// bit12-0: 电压值mV

			sCellVoltageB1[i] = cellV;			// 纯电压值(LCD按值显示), 均衡位单独存balanceStatus
			if(rawVal & 0x8000){
				balBits |= (u16)(1u << i);		// 每芯均衡位 → balanceStatus bit0~15
			}

			if(cellV > 0){						// 0 视为无效, 不参与极值
				if(cellV > cellMax){ cellMax = cellV; cellMaxIdx = i; }
				if(cellV < cellMin){ cellMin = cellV; cellMinIdx = i; }
			}
		}

		batterySum1.maxCellVoltage = cellMax;
		batterySum1.minCellVoltage = cellMin;
		batterySum1.maxCellVoltageIdx = cellMaxIdx;
		batterySum1.minCellVoltageIdx = cellMinIdx;
		batterySum1.balanceStatus = balBits;

		//--- 温度: u16 = (类型码<<13) | (℃+40), 类型 0电芯 1环境 2PCB 3MOS ---
		tempNum = p[0];
		p += 1;

		for(i = 0; i < tempNum && i < 4; i++){
			rawVal = (p[1] << 8) | p[0];
			p += 2;

			tempType = (rawVal >> 13) & 0x03;	// 类型码在高位字节 bit5-6
			rawVal   = (rawVal & 0x00FF) - 40;	// 低字节-40 = °C

			if(tempType == 0){					//电芯温度
				batterySum1.cellTemp[i] = rawVal;
				if(rawVal > cellMaxT) cellMaxT = rawVal;
				if(rawVal < cellMinT) cellMinT = rawVal;
			}else if(tempType == 1){
				batterySum1.envTemp = rawVal;
			}else if(tempType == 2){
				batterySum1.PCBTemp = rawVal;
			}else{
				batterySum1.MOSTemp = rawVal;
			}
		}
		batterySum1.maxCellTemp = cellMaxT;
		batterySum1.minCellTemp = cellMinT;

		//--- 电流 0.1A→10mA ---
		batterySum1.current = (int16_t)((p[1] << 8) | p[0]) * 10;
		p += 2;

		//--- 总压 0.1V→10mV ---
		batterySum1.voltage = ((p[1] << 8) | p[0]) * 10;
		p += 2;

		//--- SOC 0.1%→% ---
		batterySum1.SOC = ((p[1] << 8) | p[0]);
		p += 2;

		//--- SOH 0.1%→% ---
		batterySum1.SOH = ((p[1] << 8) | p[0]);
		p += 2;

		//--- 剩余容量 0.1AH ---
		batterySum1.remainCapacity = (p[1] << 8) | p[0];
		p += 2;

		//--- 满充容量 0.1AH ---
		batterySum1.fullCapacity = (p[1] << 8) | p[0];			//++
		p += 2;

		//--- 额定容量 0.1AH ---
		batterySum1.designCapacity = (p[1] << 8) | p[0];				//++
		p += 2;

		//--- battery_mode (跳过1字节) ---
		batterySum1.batteryMode = p[0];
		p += 1;
		

		//--- battery_status (1字节) ---
		batterySum1.batteryStatus = p[0];	
		p += 1;

		//--- fault_status (4字节, 小端u32) ---
		batterySum1.faultStatus = (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
		p += 4;

		//--- alarm_status (8字节, u64, 每类告警2bit等级) ---
		batterySum1.alarmStatus = (u64)p[0] | ((u64)p[1] << 8) | ((u64)p[2] << 16) | ((u64)p[3] << 24)
		                        | ((u64)p[4] << 32) | ((u64)p[5] << 40) | ((u64)p[6] << 48) | ((u64)p[7] << 56);
		p += 8;

		//--- 循环次数 ---
		batterySum1.cycle = (p[1] << 8) | p[0];
		p += 2;

		//--- 跳过累计量 (24B) + fan_speed(2) + chg_request_cur(2) = 28 ---
		batterySum1.total_chg_capacity = (p[3] << 24) | (p[2] << 16) | (p[1] << 8) | p[0];
		p+=4;
		
		batterySum1.total_dsg_capacity = (p[3] << 24) | (p[2] << 16) | (p[1] << 8) | p[0];
		p+=4;
		
		p += 18;
		
		//---chg_request_cur(2) ---
		batterySum1.chg_request_cur = (p[1] << 8) | p[0];
		p += 2;

		//--- chg_request_volt (0.1V), 存入暂存变量 ---
		batterySum1.chg_request_volt = (p[1] << 8) | p[0];
		p += 2;

		//--- 跳过 system_mode(1) ---
		batterySum1.system_mode = p[0];
		p += 1;

	//	battery1[0].batExist = 1;
	
	ProcessAllBattData1(); 
	
		return 0;
	}
	else
	{
		return 1;
	}
}


u8 ProcessAllBattData1()
{
	if(1)
	{
		for(int j = 0; j < 16; j++)
		{
			batterySum1.cellVoltage[j] = sCellVoltageB1[j];
			battery1[j].voltage = sCellVoltageB1[j];
		}
		return 1;
	}
	return 0;
}


//u8 BMSCommErrDly1 = 0;

//u8 ProcessAllBattData1() {
//	static int16_t maxCellTemp = 0;  
//	static int16_t minCellTemp = 0;  
//	static u16 batCommChangedCnt = 0;  
//	static u16 oldDesignCapacity = 0;  
//	
//	if(1)
//	{
//		batterySum1.current = 0;
//		batterySum1.remainCapacity = 0;
//		batterySum1.fullCapacity = 0;
//		batterySum1.designCapacity = 0;
//		batterySum1.batteryCnt = 0;
//		batterySum1.warningFlag = 0;
//		batterySum1.protectionFlag = 0;
//		batterySum1.statusFaultFlag = 0;
//		maxCellTemp = -1000;
//		minCellTemp = 1000;
//		
//		for(int i = 0;i<=MAX_BMS_ADDR1;i++)
//		{
//			if(battery1[i].batExist)
//			{
//				batterySum1.batteryCnt++;
//				batterySum1.warningFlag |= battery1[i].warningFlag;
//				batterySum1.protectionFlag |= battery1[i].protectionFlag;
//				batterySum1.statusFaultFlag |= battery1[i].statusFaultFlag;
//				batterySum1.voltage = battery1[i].voltage;
//				batterySum1.current += battery1[i].current;
//				batterySum1.fullCapacity += battery1[i].fullCapacity;
//				batterySum1.designCapacity += battery1[i].designCapacity;
//				batterySum1.remainCapacity += battery1[i].remainCapacity;
//				
//				for(int j= 0;j<4;j++)
//				{
//					if(battery1[i].cellTemp[j] > maxCellTemp)
//					{
//						maxCellTemp = battery1[i].cellTemp[j];
//					}
//					if(battery1[i].cellTemp[j] < minCellTemp)
//					{
//						minCellTemp = battery1[i].cellTemp[j];
//					}
//				}
//				battery1[i].maxCellTemp = maxCellTemp;
//				battery1[i].minCellTemp = minCellTemp;
//			}
//		}
//		
//		batterySum1.maxCellTemp = maxCellTemp;
//		batterySum1.minCellTemp = minCellTemp;

//		// 从单包暂存复制电芯电压到汇总结构体
//		for(int j = 0; j < 16; j++){
//			batterySum1.cellVoltage[j] = sCellVoltageB1[j];
//		}

//		// SOC/SOH 从 battery1[0] 同步
//		batterySum1.SOC = battery1[0].SOC;
//		batterySum1.SOH = battery1[0].SOH;

//		// BMS请求充电电压
//		batterySum1.chargingVoltage = sChargingVoltageB1;

//		if(batterySum1.designCapacity!=oldDesignCapacity && oldDesignCapacity>0)
//		{
//			batCommChangedCnt++;
//			if(batCommChangedCnt>=3)
//			{
//				oldDesignCapacity = batterySum1.designCapacity;
//			}
//		}
//		else
//		{
//			batCommChangedCnt = 0;
//			oldDesignCapacity = batterySum1.designCapacity;
//		}
//		
//		if(batterySum1.fullCapacity>0)
//		{
//			SysParam.warningCode2Bits.BMSCommLoss = 0;
//			SysParam.warningCode2Bits.cellOverVoltage = batterySum1.warningFlagBit.COV;
//			SysParam.warningCode2Bits.cellUnderVoltage = batterySum1.warningFlagBit.CUV;
//			SysParam.warningCode1Bits.VbatHigh_W = batterySum1.warningFlagBit.POV;
//			SysParam.warningCode1Bits.VbatLow_W = batterySum1.warningFlagBit.PUV;
//			SysParam.warningCode2Bits.batOverDisCharged = batterySum1.warningFlagBit.OCD;
//			SysParam.warningCode2Bits.batOverCharged = batterySum1.warningFlagBit.OCC;
//			SysParam.warningCode2Bits.overTempDischarge = batterySum1.warningFlagBit.OTD;
//			SysParam.warningCode2Bits.overTempCharge = batterySum1.warningFlagBit.OTC;		
//			SysParam.warningCode2Bits.MOSOvertemp = batterySum1.warningFlagBit.MOT;
//			SysParam.warningCode2Bits.batOvertemp = 0;
//			SysParam.warningCode2Bits.batUndertemp = 0;
//			SysParam.warningCode2Bits.systemShutdown = 0;
//			BMSCommErrDly1 = 0;
//			SysParam.BMSDisconnected = 0;
//			batterySum1.SOC = (float)batterySum1.remainCapacity*100/batterySum1.fullCapacity;
//		}
//		else
//		{
//			BMSCommErrDly1++;
//			if(BMSCommErrDly1>=2)
//			{
//				SysParam.BMSDisconnected = 1;
//				SysParam.warningCode2 = 0;
//			}
//		}
//		return 1;
//	}
//	return 0;
//}

void ProcessUsart0Com1(void)
{
	/** BMS **/
	static u8 BMSCommStat = USART0_BMS_TRANSMIT1;
	static u8 BMSRcvTimeout = 0;
	
	if((inverterParam1.configWord.bits.isLiBat && inverterParam1.configWord1.bits.RS485Protocol==BBJ_BMS_PROTOCOL ))		//&& SysParam.inverter_status1.Master_Slave
	{
				switch(BMSCommStat) {
					case USART0_BMS_TRANSMIT1:
//						BMSRcvTimeout = 0;
						BMSCommStat = USART0_BMS_RECV1;
						Usart0BMSTransmit1();
					break;
					case USART0_BMS_RECV1:				
						if(USART0_RxDataIsReady) {
							USART0_RxDataIsReady = 0;
							BMSRcvTimeout = 0;
							if(RcvBMSPacket1() == 0){
								ReceiveNewFlag = 1;
							}
						} else {
							if(BMSRcvTimeout++>=3) //没有接收到BMS返回的电源信息
							{				
								ReceiveNewFlag = 0;
								BMSRcvTimeout = 0;
							}
						}
						
						//统计电源信息,累加到电池
//							ProcessAllBattData1()
							BMSCommStat = USART0_BMS_TRANSMIT1;

					break;
		}
	}
	else
	{
		ReceiveNewFlag = 0;
		BMSCommStat = USART0_BMS_TRANSMIT1;
	}

	
//	LiBMSDecideChgCurrVolt1();
	// Li2UserLi();
}



//u16 BMSMaxChgCurr1 = 0;
//u16 BMSChargingVoltage1 = 0;
//void LiBMSDecideChgCurrVolt1(void) {

//	static u8 DelayCnt = 0;
//			
//	//ֻ��﮵��ģʽ����BMS���ó�������SysParam.BMSMaxChgCurr1
//	if(inverterParam.configWord.bits.isLiBat /* && SysParam.inverter_status1.ParallelStatus==ParallelMaster */) {
//		if(DelayCnt++>10)
//		{
//			DelayCnt = 0;
//			if(!SysParam.BMSDisconnected && batterySum.SOC!=0xff) {

//				if(batterySum.designCapacity>0) {
//					BMSMaxChgCurr1 = batterySum.designCapacity/100;
//				}
//			
//				//����ѹ
//				BMSChargingVoltage1 = batterySum.chargingVoltage/10;
//				if(SysParam.LiChgVolt!=BMSChargingVoltage1) {
//					inverterParam.VbatChgSetting = BMSChargingVoltage1/4;
//					inverterParam.floatChgVolt = BMSChargingVoltage1/4;
//					CMD2FToDsp_SettingChgVoltFlag = 1;
//				}

//				//������
//				if(BMSMaxChgCurr1!=0) {
//					if(batterySum.SOC>98) {
//						SysParam.BMSMaxChgCurr1 = BMSMaxChgCurr1*7/160;
//					}
//					else if(batterySum.SOC>95) {
//						SysParam.BMSMaxChgCurr1 = BMSMaxChgCurr1*7/40;
//					}
//					else {
//						SysParam.BMSMaxChgCurr1 = BMSMaxChgCurr1*7/10;
//					}
//					
//					inverterParam.maxChgCurr = SysParam.BMSMaxChgCurr1;
//					if(SysParam.BMSMaxChgCurr1 > SysParam.EEMaxChgCurr)
//					{
//						inverterParam.maxChgCurr = SysParam.EEMaxChgCurr;
//					}
//					
//					inverterParam.maxUtlChgCurr = SysParam.BMSMaxChgCurr1;
//					if(SysParam.BMSMaxChgCurr1 > SysParam.EEMaxUtlChgCurr)
//					{
//						inverterParam.maxUtlChgCurr = SysParam.EEMaxUtlChgCurr;
//					}
//					
//					if(SysParam.DSPmaxChgCurr != inverterParam.maxChgCurr || SysParam.DSPmaxUtlChgCurr != inverterParam.maxUtlChgCurr)
//					{
//						CMD17ToDsp_SettingMaxChgCurrFlag = 1;
//					}
//				}
//			}
//			else
//			{
//				inverterParam.maxChgCurr = 10;
//				inverterParam.maxUtlChgCurr = 10;
//				CMD17ToDsp_SettingMaxChgCurrFlag = 1;
//			}
//		}
//	}
//}




