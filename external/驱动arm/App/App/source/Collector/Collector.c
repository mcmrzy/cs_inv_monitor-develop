
#include "Collector.h"
#include "TEA.h"
#include "delay.h"
#include "queue.h"
#include "_string.h"
#include "Task.h"
#include "OSAL_Memory.h"
#include "EnergySatistics.h"
#include "SystemManage.h"
#include "ComProtocol.h"
#include "CollectorParamAddr.h"
#include "SmartSwitch.h"
#include "Fan_Temperature.h"
#include "USERFLASH.h"
#include "USARTBMS0.h"

#pragma pack(1)
typedef struct
{
    u8  header;
    u16 CmdLen;
    u8  cmd;
    u16 param1;
    u16 param2;
    u8  data[];      
}CollectorCmdDef;
#pragma pack()

u16 CollectorConnect=0;

extern u32 CRC32_HW(unsigned int *pBuff, u32 CrcInitValue,u32 size);
void InvRxTimeOutManage(void);
u8 updateInverterParam(inverterParam_t*pInverterParam);
void CollectorDataFrameHander(void);
void InstructionProcess(u8 *pInstruct);
void ReadUserCtrlParam(CollectorCmdDef *instruct);
void ReadRunParam(CollectorCmdDef *instruct);
void WriteUserCtrlParam(CollectorCmdDef *instruct);
void ReadCanReadWriteData(CollectorCmdDef *instruct);
void WriteCanReadWriteData(CollectorCmdDef *instruct);
void ReadOnlyReadData(CollectorCmdDef *instruct);
void ReadTestRunParam(CollectorCmdDef *instruct);

extern u8 SwitchDetect(void);

void  CollectorTaskFunc(void)
{
    SetTaskDly(CollectorTaskID,_100ms);
    CollectorDataFrameHander();
}

void CollectorDataFrameHander(void)
{   
	u8 data;
    
	while(USARTCmdData.stataus!=RCVFINISH && delete_queue(&UartReadQu,&data)){
		
		PPPFrameCmdReceive(&USARTCmdData,data);			//PPP协议的解封装
	}
	
	if(USARTCmdData.stataus==RCVFINISH)
	{	
        u32 TempKey[4];
        DecryptData(USARTCmdData.RCdata,FrameKey,USARTCmdData.length);//数据解密
        _memcpy(TempKey,FrameKey,8);
        _memcpy(&TempKey[2],USARTCmdData.RCdata+USARTCmdData.length-8,8);
        DecryptData(USARTCmdData.RCdata,TempKey,USARTCmdData.length);//第二次解密
        InstructionProcess(USARTCmdData.RCdata);  //执行指令处理    
        StartRcv();      //重新接受状态  
	}else{
	   if(CollectorConnect){
           CollectorConnect--;
       }
	} 
    InvRxTimeOutManage();		//超时管理  
}


void InstructionProcess(u8 *pInstruct)
{
    CollectorCmdDef *instruct;  
    u32 crc32;
    
    instruct=(CollectorCmdDef *)pInstruct;
    if(instruct->header!=0xAA){
        return;
    }
    
    if(instruct->CmdLen<8 || instruct->CmdLen%4){//必须为4的整数倍，避免内存非对齐访问错误
        return;
    }
    crc32=*(u32*)&instruct->data[instruct->CmdLen-8];
    if(CRC32_HW((u32*)instruct,0xFFFFFFFF,instruct->CmdLen>>2)!=crc32){
        return;//CRC校验不过
    }

   CollectorConnect=1200;//120秒计时
   switch(instruct->cmd)
   {
       case READ_CTRLPARAM:
           ReadUserCtrlParam(instruct);
       break;
       
       case WRITE_CTRLPARAM:
           WriteUserCtrlParam(instruct);
       break;
       
       case READ_RUNPARAM:
           ReadRunParam(instruct); 
       break;
       
       case READ_R_W_DATA:
           ReadCanReadWriteData(instruct);
       break;
       
       case WRITE_R_W_DATA:
           WriteCanReadWriteData(instruct);
       break;
       
       case READ_R_DATA:
           ReadOnlyReadData(instruct);
       break;
       
       case CTRLCMD:
           
       break;
       
       case 0x14://待测试运行参数
           ReadTestRunParam(instruct);
       break;
       
       default :
                 
       break;  
   }       
}


void ReadUserCtrlParam(CollectorCmdDef *instruct)
{
    u8 *pmemaddr;
    u16 *pSysParam,EncryptLen;
    CollectorCmdDef *pInstruct;
    u32 crc32,pSysParamoffset,pInstructoffset;
    u32 TempKey[4];    
    u8 BatTypeIndex[6]={0,1,2,4,3,5};
    u8 ChgPrioTransTable[5]={0,1,0,2,3};//SOL=>01, SOL+UTL=>03,ONLYSOL=>04,//1:Solar First;2:Solar+Utility; 3:Only Solar
    
     //AGA=>01, FLD=>02, , USE=>03, LI=>04, US2=>05,
    pmemaddr=(u8*)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pSysParamoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pSysParamoffset;        
    }else{
        pSysParamoffset=0;
    }
    pSysParam=(u16*)pmemaddr;
    
    if(instruct->param2==0 || (instruct->param1%2)==1||(instruct->param2%2==1)){
        free(((u8*)pSysParam)-pSysParamoffset);       
        return;//��������
    }
    
    if((instruct->param1+instruct->param2)>ConfigParamMaxIndex){
        free(((u8*)pSysParam)-pSysParamoffset);
        return;//���ʵ�ַ������Χ 
    }
    
    pSysParam[Index_OutputPriority]        =inverterParam1.output_src_prio;
    pSysParam[Index_MaxChargeCurrentAll]   =SysParam.EEMaxChgCurr;
    pSysParam[Index_ACInVoltRange]         =inverterParam1.ac_input_volt_range;//APL=>01, GEN=>03, UPS=>02, 
    pSysParam[Index_BatCapacity]           =SysParam.BatCapacity;
    pSysParam[Index_BatteryType]           =BatTypeIndex[inverterParam1.batteryType];// DSP ��Ӧ��ϵΪ AGA=>01, FLD=>02, , USE=>03, LI=>04, US2=>05,
    pSysParam[Index_OverloadRestart]       =inverterParam1.configWord.bits.overload_restart;
    pSysParam[Index_HighTemperatureRestart]=inverterParam1.configWord.bits.overtemp_restart;
    pSysParam[Index_OutputVoltage]         =inverterParam1.output_voltage/10;
    pSysParam[Index_OutputFrequency]       =inverterParam1.output_frequency/10;//��λ0.1Hz
    pSysParam[Index_Master_Slave]          =inverterParam1.configWord1.bits.parallelMaster;
    pSysParam[Index_MaxChargeCityCurrent]  =SysParam.EEMaxUtlChgCurr;
    pSysParam[Index_LowVoltReturnCityPower]=inverterParam1.volt_point_2_utl/10;//��ѹת��
    pSysParam[Index_HighVoltReturnBattery] =inverterParam1.volt_point_2_bat/10;//��ѹת��   
    pSysParam[Index_BatteryChargePriority] =ChgPrioTransTable[inverterParam1.chg_src_prio];//DSP ��Ӧ��ϵΪ SOL=>01, ONLYSOL=>04,SOL+UTL=>03
    pSysParam[Index_AlarmControl]          =inverterParam1.configWord1.bits.alarm_control; 
    pSysParam[Index_BackLightCtrl]         =SysParam.BacklightEn;
    pSysParam[Index_PowerShutdownAlarm]    =inverterParam1.configWord.bits.pri_src_intr_alarm;
    pSysParam[Index_OverloadUseCityPower]  =inverterParam1.configWord.bits.overload_bypass;   
    pSysParam[Index_ParaMaxDisChgCurr]     =SysParam.ParaMaxDisChgCurr;//����ϵͳ���ŵ����
    pSysParam[Index_ParaMaxChgCurr]        =SysParam.ParaMaxChgCurr;//����ϵͳ��������
    pSysParam[Index_RecoverThresholdVolt]=1;//!!!
    pSysParam[Index_SolarPowerBalance]     =inverterParam1.configWord.bits.solar_power_balance;
    pSysParam[Index_ACOutputMode]          =inverterParam1.parallelSetting;
    pSysParam[Index_LiBatMaterial]         =SysParam.BatMaterial;
    pSysParam[Index_CellInSerial_LiFePO4]  =SysParam.BatSerial_LiFePO4;
    pSysParam[Index_CellInSerial_Li_NMC]   =SysParam.BatSerial_LiNMC; 
    pSysParam[Index_EqEnable]           =inverterParam1.configWord.bits.equalization_enable;
    pSysParam[Index_EqVoltageSet]       =inverterParam1.equalization_voltage;
    pSysParam[Index_EqTimeSet]          =inverterParam1.equalized_time;
    pSysParam[Index_EqtTimeoutSet]      =inverterParam1.equalized_timeout;
    pSysParam[Index_EqtIntervalSet]     =inverterParam1.equalized_interval;
    pSysParam[Index_EqactivateSet]      =SysParam.EqactivateSet;   
    pSysParam[Index_ChargeTimeSet]     =inverterParam1.utilityChargingTime<<8;
    pSysParam[Index_CloseChargeTimeSet]=inverterParam1.utilityChargingTime1<<8;   
    pSysParam[Index_LVoltOpenGenerator] =SysParam.GeStartVoltage*10;
    pSysParam[Index_HVoltCloseGenerator]=SysParam.GeStopVoltage*10;       
    pSysParam[Index_SocBackUtl]         =inverterParam1.soc_point_2_utl;
    pSysParam[Index_SocBackBat]         =inverterParam1.soc_point_2_bat;
    pSysParam[Index_SocBackGen]         =SysParam.GeStartSOC;
    pSysParam[Index_SocCloseGen]        =SysParam.GeStopSOC;
    pSysParam[Index_Soccutoff]          =inverterParam1.cutoff_soc;   
    pSysParam[Index_BuzzerEN]           =SysParam.BuzzerEn;   
	
//		pSysParam[Index_S_GradeSOC]         =smartSwitch.SLevelSOCThres;
//    pSysParam[Index_A_GradeSOC]         =smartSwitch.ALevelSOCThres;
//    pSysParam[Index_B_GradeSOC]         =smartSwitch.BLevelSOCThres;
//    pSysParam[Index_ManualSocket]       = smartSwitch.ManualSocket;
//    pSysParam[Index_ControlSocket]      = smartSwitch.ControlSocket;
	
    pSysParam[Index_RecoverThresholdSoc]=1;//!!!
    pSysParam[Index_LiBatProtocolType]   =inverterParam1.configWord1.bits.RS485Protocol;
    pSysParam[Index_GenRateWatt]         =SysParam.GeRatedPower;
    pSysParam[Index_GeBalanceEn]         =SysParam.GeBalanceEn;  
    pSysParam[Index_GenWorkStartTime1L]  =SysParam.GenWorkStartTime1;
    pSysParam[Index_GenWorkStartTime1H]  =SysParam.GenWorkStartTime1>>16;
    pSysParam[Index_GenWorkEndTime1L]    =SysParam.GenWorkEndTime1;
    pSysParam[Index_GenWorkEndTime1H]    =SysParam.GenWorkEndTime1>>16;
    pSysParam[Index_GenWorkStartTime2L]  =SysParam.GenWorkStartTime2;
    pSysParam[Index_GenWorkStartTime2H]  =SysParam.GenWorkStartTime2>>16;
    pSysParam[Index_GenWorkEndTime2L]    =SysParam.GenWorkEndTime2;
    pSysParam[Index_GenWorkEndTime2H]    =SysParam.GenWorkEndTime2>>16;    
    pSysParam[Index_UtiOutputStartTime1L]=SysParam.UtiOutputStartTime1;
    pSysParam[Index_UtiOutputStartTime1H]=SysParam.UtiOutputStartTime1>>16;
    pSysParam[Index_UtiOutputEndTime1L]  =SysParam.UtiOutputEndTime1;
    pSysParam[Index_UtiOutputEndTime1H]  =SysParam.UtiOutputEndTime1>>16;
    pSysParam[Index_UtiOutputStartTime2L]=SysParam.UtiOutputStartTime2;
    pSysParam[Index_UtiOutputStartTime2H]=SysParam.UtiOutputStartTime2>>16;
    pSysParam[Index_UtiOutputEndTime2L]  =SysParam.UtiOutputEndTime2;
    pSysParam[Index_UtiOutputEndTime2H]  =SysParam.UtiOutputEndTime2>>16; 
    pSysParam[Index_VbatAgm]         		 =SysParam.EEBatAgmVbat<<2;
    pSysParam[Index_VbatFlood]       =SysParam.EEBatFloodVbat<<2;  
    pSysParam[Index_VbatUserPb]      =SysParam.EEBatUserPbVbat<<2;
    pSysParam[Index_VbatAgmFloat]        =SysParam.EEBatAgmVfloat<<2;
    pSysParam[Index_VbatFloodFloat]      =SysParam.EEBatFloodVfloat<<2;
    pSysParam[Index_VbatLiFloat]         =SysParam.EEBatLiVfloat<<2;
    pSysParam[Index_VbatUserPbFloat]     =SysParam.EEBatUserPbVfloat<<2;  
    pSysParam[Index_VbatUserLiFeFloat]   =((SysParam.EEBatUserLiFeVfloat<<2)+(SysParam.BatSerial_LiFePO4>>1))/SysParam.BatSerial_LiFePO4;
    pSysParam[Index_VbatUserLiNmcFloat]  =((SysParam.EEBatUserLiNMCVfloat<<2)+(SysParam.BatSerial_LiNMC>>1))/SysParam.BatSerial_LiNMC;
    pSysParam[Index_VbatAgmCutOff]       =SysParam.EEBatAgmVcutoff<<2;  
    pSysParam[Index_VbatFloodCutOff]     =SysParam.EEBatFloodVcutoff<<2;
    pSysParam[Index_VbatLiCutOff]        =SysParam.EEBatLiVcutoff<<2;
    pSysParam[Index_VbatUserPbCutOff]    =SysParam.EEBatUserPbVcutoff<<2;
    pSysParam[Index_VbatUserLiFeCutOff]  =((SysParam.EEBatUserLiFeVcutoff<<2)+(SysParam.BatSerial_LiFePO4>>1))/SysParam.BatSerial_LiFePO4;
    pSysParam[Index_VbatUserLiNmcCutOff] =((SysParam.EEBatUserLiNMCVcutoff<<2)+(SysParam.BatSerial_LiNMC>>1))/SysParam.BatSerial_LiNMC;  
    pSysParam[Index_SocMaxUtlChg]=SysParam.SocMaxUtlChg;
    pSysParam[Index_VMaxUtlChg]=SysParam.VMaxUtlChg*10;
            
////////////////////////////////////////////////////////////////////////////////////////    
    pmemaddr=(u8 *)malloc(256);    
    if(!pmemaddr){
        free(((u8*)pSysParam)-pSysParamoffset);
        return;
    }
    
    if((u32)pmemaddr%4){
        pInstructoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pInstructoffset;        
    }else{
        pInstructoffset=0;
    }
    pInstruct=(CollectorCmdDef *)pmemaddr;
    
    _memset((u8*)pInstruct,0,256-pInstructoffset);
    pInstruct->header=instruct->header;
    pInstruct->cmd=instruct->cmd;
    pInstruct->CmdLen=((instruct->param2+8+3)>>2)<<2;//���ȱ���Ϊ4��������
    pInstruct->param1=instruct->param1;
    pInstruct->param2=instruct->param2;
    _memcpy(pInstruct->data,&pSysParam[instruct->param1>>1],instruct->param2);
    free(((u8*)pSysParam)-pSysParamoffset);
    
    crc32=CRC32_HW((u32*)pInstruct,0xFFFFFFFF,pInstruct->CmdLen>>2);

    pInstruct->data[pInstruct->CmdLen-8]=crc32;    
    pInstruct->data[pInstruct->CmdLen-7]=crc32>>8;
    pInstruct->data[pInstruct->CmdLen-6]=crc32>>16;
    pInstruct->data[pInstruct->CmdLen-5]=crc32>>24;
    EncryptLen=((pInstruct->CmdLen+4+7)>>3)<<3;
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    EncryptData((u8*)pInstruct, TempKey,EncryptLen);
    _memcpy(((u8*)pInstruct)+EncryptLen,&TempKey[2],8);
    EncryptLen+=8;
    EncryptData((u8*)pInstruct, FrameKey,EncryptLen);     
    PppSend((u8*)pInstruct,EncryptLen);
    
    free(((u8*)pInstruct)-pInstructoffset);
        
}


extern s16 batChgCurr;
extern s16 batDsgCurr;
void ReadRunParam(CollectorCmdDef *instruct)
{
    u8 *pmemaddr;
    u16 EncryptLen;
    CollectorCmdDef *pInstruct;
    u32 crc32,pRunParamoffset,pInstructoffset;
    u32 TempKey[4];
    RunParamDef *pRunParam;
    u16 k;

    pmemaddr=(u8*)malloc(512);    /* RunParamDef 扩展后 >256 字节(现270), 缓冲必须大于结构体 */
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pRunParamoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pRunParamoffset;        
    }else {
        pRunParamoffset=0;
    }
    pRunParam=(RunParamDef *)pmemaddr;
    
    
    if(instruct->param2==0 || (instruct->param1%2)==1||(instruct->param2%2==1)){
        free(((u8*)pRunParam)-pRunParamoffset);       
        return;//参数有误
    }
    
    if(instruct->param1<RunParamStartIndex  || (instruct->param1+(instruct->param2>>1)) >(RunParamEndIndex+1)){
        free(((u8*)pRunParam)-pRunParamoffset);
        return;//范问地址超过范围 
    }
    
	
    pRunParam->SysStatus=0;
	if(SwitchDetect()==0) {
		pRunParam->SysStatusBits.StandBy =1; 
	} 
	
	if(SysParam.errorCode!=0 || ArmDspComm.tick==0) {
		pRunParam->SysStatusBits.Fault = 1 ;
	} 
	// UIStatus.Bit.BatStatus=0;//0:无电池;1：在充电;2:在放电;3:有电池且无充电和放电
    if(UIStatus.Bit.BatStatus==1){
        pRunParam->SysStatusBits.Charge=1;
    }else if(UIStatus.Bit.BatStatus==2) {
		pRunParam->SysStatusBits.Discharging = 1;
	}

    if(UIStatus.Bit.PvStatus==1){
        pRunParam->SysStatusBits.Pvinput=1;
    }else if(UIStatus.Bit.PvStatus==2) {
		pRunParam->SysStatusBits.PVCharging = 1;
        pRunParam->SysStatusBits.Pvinput=1;
	} 
	
	if(UIStatus.Bit.UtStatus && UIStatus.Bit.UtCharge) {
		pRunParam->SysStatusBits.ACCharging = 1;
	}else if(UIStatus.Bit.UtStatus&& UIStatus.Bit.GeStatus==0){
        pRunParam->SysStatusBits.AcInput = 1;
    }
		
	if(UIStatus.Bit.GeStatus && UIStatus.Bit.UtCharge) {
		pRunParam->SysStatusBits.GenCharging = 1;
	}else if(UIStatus.Bit.GeStatus){
        pRunParam->SysStatusBits.GeInput= 1;
    }
	
//	if(SysParam.inverter_status.ACOutput && SysParam.inverter_status.ACBypass) {
//		pRunParam->SysStatusBits.ACBypass = 1;
//	}
//		if(SysParam.ModeNum==16) pRunParam->SysStatusBits.ACBypass = 1;
		if(SysParam.inverter_status.RelayAcL) pRunParam->SysStatusBits.ACBypass = 1;
		
    if(UIStatus.Bit.ACOutStatus){
        pRunParam->SysStatusBits.ToLoad=1;
    }    
    
		pRunParam->Vpv1=SysParam.Vpv1;
    pRunParam->Vpv2=SysParam.Vpv2;
//    pRunParam->Ppv=SysParam.Ppv1+SysParam.Ppv2;
    pRunParam->Buck1Curr=0;
    pRunParam->Buck2Curr=0;
    pRunParam->BoostTemp=Temperature_Struct.LV_MOS*10;
    pRunParam->InvertTemp=Temperature_Struct.HV_IGBT*10;
    if(SysParam.Pload<0){
        SysParam.Pload=0;
    }
    pRunParam->OutputWatt=SysParam.Pload;
    pRunParam->OutputVA=SysParam.Sload;
    pRunParam->OutputCurr=SysParam.IloadA;
    pRunParam->ACChrWatt=SysParam.Pgrid;
    pRunParam->ACChrVA=SysParam.Sgrid;//无VA参数
    pRunParam->GridVolt=SysParam.VgridA;
    pRunParam->GridFreq=SysParam.GridFreq;
    pRunParam->ACOutputVolt=SysParam.VloadA;
    pRunParam->ACOutputFreq=SysParam.LoadFreq;
    pRunParam->ACInWatt=SysParam.Pgrid;
    pRunParam->ACInVA=SysParam.Sgrid;//无VA
    pRunParam->ACDisChrWatt=SysParam.Pgrid;
    pRunParam->ACDisChrVA=SysParam.Sgrid;
    pRunParam->ACChrCurr=SysParam.IgridA;
    pRunParam->BatVolt=SysParam.VbatA*10;
    pRunParam->BatterySOC=SysParam.BatPercent;
    if(pRunParam->BatterySOC>100){
        pRunParam->BatterySOC=0;
    }
    pRunParam->BatDisChrWatt=SysParam.Pbat;
    pRunParam->BatChrWatt=SysParam.Pbat;
    pRunParam->BatChgCurr=batChgCurr;
    pRunParam->BatDischgCurr=batDsgCurr;
    pRunParam->BatOverCharge=SysParam.warningCode2Bits.batOverCharged;
    pRunParam->BusVolt=SysParam.BusVoltage/10;
//    pRunParam->PvTemp=Temperature_Struct.PV*10;
    pRunParam->InvCurr=0;//未知
//    pRunParam->TransformerTemp=Temperature_Struct.Transformer*10;
    pRunParam->LoadPercent=SysParam.LoadPercent;
    pRunParam->ParaChgCurr=0;//未知
    pRunParam->WorkTimeTotal=0;//未实现
    pRunParam->MpptFanSpeed=0;
    pRunParam->InvFanSpeed=0;
	
//    pRunParam->PairedSocket= smartSwitch.ExistSocket;//已配对从机
//    pRunParam->OnlineSocket= smartSwitch.OnlineSocket;//在线从机
//		pRunParam->OnSocket= smartSwitch.SocketStatus;	 //从机开关状态
					
    union{
        struct{
        u16 parallelNoBat:1,//警告码22,parallel fibidden without battery
				fan2Locked  :				1,//警告码17 ,the invert fan is locked	
				ParaVerDiff      :1,//警告码18,parallel version different
				UnstableGridFrq  :1,//警告码19,grid frequency unstable
            reserved2:12;
        }bits;
        u16 word;   
    } tempWarningCode1;  //转换成与服务器端协议相同的定义
	
//	tempWarningCode1.bits.parallelNoBat = SysParam.warningCode1Bits.parallelNoBat;
//	tempWarningCode1.bits.fan2Locked = SysParam.warningCode1Bits.Fan1Locked | SysParam.warningCode1Bits.Fan2SpeedLow;
//	tempWarningCode1.bits.ParaVerDiff = SysParam.warningCode1Bits.ParaVerDiff;
//	tempWarningCode1.bits.UnstableGridFrq = SysParam.warningCode1Bits.UnstableGridFrq;
	
	u16 tempWarningCode = SysParam.warningCode1;
	if(SysParam.warningCode1Bits.Fan1SpeedLow || SysParam.warningCode1Bits.Fan2SpeedLow) {
		tempWarningCode |= 0x1;
	} else {
		tempWarningCode &= 0xfffe;
	}
	
    pRunParam->Warning=(tempWarningCode1.word<<16)|tempWarningCode;
    pRunParam->BmsWarning=SysParam.warningCode2&0x1FFF;
    pRunParam->FaultValue=SysParam.errorCode;
   
    pRunParam->EGen_today=Statistics.EGenerator_Today/100/3600;//发电机今日总发电量
    pRunParam->EGen_total=Statistics.EGenerator_Total;//发电机总发电量
    pRunParam->Epv_today=Statistics.EpvToday/100/3600;
    pRunParam->Epv_total=Statistics.EpvTotal;
//    pRunParam->Epv2_today=0;
//    pRunParam->Epv2_total=0;   
    pRunParam->Eac_chrToday=Statistics.Eac_chrToday/100/3600;//AC今日充电
    pRunParam->Eac_chrTotal=Statistics.Eac_chrTotal;//AC总充电    
    pRunParam->Ebat_dischrToday=Statistics.Ebat_dischrToday/100/3600;//电池今日放电
    pRunParam->Ebat_dischrTotal=Statistics.Ebat_dischrTotal;//电池总放电   
    pRunParam->Ebat_chrToday=Statistics.Ebat_chrToday/100/3600;;//电池今日充电
    pRunParam->Ebat_chrTotal=Statistics.Ebat_chrTotal;//电池总放电   
    pRunParam->Eac_dischrToday=Statistics.Eac_dischrToday/100/3600;//AC旁路放电
    pRunParam->Eac_dischrTotal=Statistics.Eac_dischrTotal;//AC旁路总放电   
    pRunParam->Eop_dischrToday=Statistics.Eop_dischrToday/100/3600;//负载今日放电
    pRunParam->Eop_dischrTotal=Statistics.Eop_dischrTotal;//负载总放电

    /* ---- BMS 扩展组: 数据源 batterySum1(储能BMS PC485协议), 字段定义见 CollectorParamAddr.h ---- */
    if(ReceiveNewFlag){
        pRunParam->BmsOnline = 1;
        pRunParam->BmsSoc = batterySum1.SOC;
        pRunParam->BmsSoh = batterySum1.SOH;
        pRunParam->BmsRemainCap = batterySum1.remainCapacity;
        pRunParam->BmsFullCap = batterySum1.fullCapacity;
        pRunParam->BmsDesignCap = batterySum1.designCapacity;
        pRunParam->BmsCycleCnt = batterySum1.cycle;
        pRunParam->BmsCellVoltMax = batterySum1.maxCellVoltage;
        pRunParam->BmsCellVoltMin = batterySum1.minCellVoltage;
        pRunParam->BmsCellVoltDiff = (batterySum1.minCellVoltage > 0) ?
                                     (batterySum1.maxCellVoltage - batterySum1.minCellVoltage) : 0;
        pRunParam->BmsCellVoltMaxIdx = batterySum1.maxCellVoltageIdx;
        pRunParam->BmsCellVoltMinIdx = batterySum1.minCellVoltageIdx;
        pRunParam->BmsCellTempMax = batterySum1.maxCellTemp;
        pRunParam->BmsCellTempMin = batterySum1.minCellTemp;
        pRunParam->BmsMosTemp = batterySum1.MOSTemp;
        pRunParam->BmsEnvTemp = batterySum1.envTemp;
        pRunParam->BmsPcbTemp = batterySum1.PCBTemp;
        pRunParam->BmsBatteryMode = batterySum1.batteryMode;
        pRunParam->BmsMOSStatus = batterySum1.batteryStatus;
        pRunParam->BmsSystemMode = batterySum1.system_mode;
        pRunParam->BmsChgRequestCur = batterySum1.chg_request_cur;
        pRunParam->BmsChgRequestVolt = batterySum1.chg_request_volt;
        pRunParam->BmsFaultStatusL = (u16)(batterySum1.faultStatus & 0xFFFF);
        pRunParam->BmsFaultStatusH = (u16)(batterySum1.faultStatus >> 16);
        pRunParam->BmsAlarmW0 = (u16)(batterySum1.alarmStatus & 0xFFFF);
        pRunParam->BmsAlarmW1 = (u16)((batterySum1.alarmStatus >> 16) & 0xFFFF);
        pRunParam->BmsAlarmW2 = (u16)((batterySum1.alarmStatus >> 32) & 0xFFFF);
        pRunParam->BmsTotalChgCap = batterySum1.total_chg_capacity;
        pRunParam->BmsTotalDsgCap = batterySum1.total_dsg_capacity;
        for(k = 0; k < 16; k++){
            /* 值=bit12-0(mV), bit15=该芯均衡中(与BMS PC协议上报格式一致) */
            pRunParam->BmsCellVolt[k] = batterySum1.cellVoltage[k]
                                      | (((batterySum1.balanceStatus >> k) & 1) ? 0x8000 : 0);
        }
    }else{
        pRunParam->BmsOnline = 0;
        pRunParam->BmsSoc = 0xFFFF;
        pRunParam->BmsSoh = 0xFFFF;
        pRunParam->BmsRemainCap = 0xFFFF;
        pRunParam->BmsFullCap = 0xFFFF;
        pRunParam->BmsDesignCap = 0xFFFF;
        pRunParam->BmsCycleCnt = 0xFFFF;
        pRunParam->BmsCellVoltMax = 0xFFFF;
        pRunParam->BmsCellVoltMin = 0xFFFF;
        pRunParam->BmsCellVoltDiff = 0xFFFF;
        pRunParam->BmsCellVoltMaxIdx = 0xFFFF;
        pRunParam->BmsCellVoltMinIdx = 0xFFFF;
        pRunParam->BmsCellTempMax = -1000;
        pRunParam->BmsCellTempMin = -1000;
        pRunParam->BmsMosTemp = -1000;
        pRunParam->BmsEnvTemp = -1000;
        pRunParam->BmsPcbTemp = -1000;
        pRunParam->BmsBatteryMode = 0xFFFF;
        pRunParam->BmsMOSStatus = 0xFFFF;
        pRunParam->BmsSystemMode = 0xFFFF;
        pRunParam->BmsChgRequestCur = 0xFFFF;
        pRunParam->BmsChgRequestVolt = 0xFFFF;
        pRunParam->BmsFaultStatusL = 0xFFFF;
        pRunParam->BmsFaultStatusH = 0xFFFF;
        pRunParam->BmsAlarmW0 = 0xFFFF;
        pRunParam->BmsAlarmW1 = 0xFFFF;
        pRunParam->BmsAlarmW2 = 0xFFFF;
        pRunParam->BmsTotalChgCap = 0xFFFFFFFF;
        pRunParam->BmsTotalDsgCap = 0xFFFFFFFF;
        for(k = 0; k < 16; k++){
            pRunParam->BmsCellVolt[k] = 0xFFFF;
        }
    }
	

////////////////////////////////////////////////////////////////////////////////////////    
    pmemaddr=(u8 *)malloc(512);    /* 应答含BMS扩展组, 数据区最长270字节, 256不够 */
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pInstructoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pInstructoffset;        
    }else{
        pInstructoffset=0;
    }
    pInstruct=(CollectorCmdDef *)pmemaddr;
    
    _memset((u8*)pInstruct,0,512-pInstructoffset);
    pInstruct->header=instruct->header;
    pInstruct->cmd=instruct->cmd;
    pInstruct->CmdLen=((instruct->param2+8+3)>>2)<<2;//长度必须为4的整数倍
    pInstruct->param1=instruct->param1;
    pInstruct->param2=instruct->param2;
    
    u16 *RunParam=(u16*)pRunParam;
    _memcpy(pInstruct->data,&RunParam[(instruct->param1-RunParamStartIndex)>>1],instruct->param2);
    free(((u8*)pRunParam)-pRunParamoffset);
    
    crc32=CRC32_HW((u32*)pInstruct,0xFFFFFFFF,pInstruct->CmdLen>>2);

    pInstruct->data[pInstruct->CmdLen-8]=crc32;    
    pInstruct->data[pInstruct->CmdLen-7]=crc32>>8;
    pInstruct->data[pInstruct->CmdLen-6]=crc32>>16;
    pInstruct->data[pInstruct->CmdLen-5]=crc32>>24;
    EncryptLen=((pInstruct->CmdLen+4+7)>>3)<<3;
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    EncryptData((u8*)pInstruct, TempKey,EncryptLen);
    _memcpy(((u8*)pInstruct)+EncryptLen,&TempKey[2],8);
    EncryptLen+=8;
    EncryptData((u8*)pInstruct, FrameKey,EncryptLen);     
    PppSend((u8*)pInstruct,EncryptLen);
    
    free(((u8*)pInstruct)-pInstructoffset);
}


void WriteUserCtrlParam(CollectorCmdDef *instruct)
{
    u8 err=0;
    u16 Index, *pParam;
    u8 BatTypeIndex[6]={0,1,2,4,3,5};
    u8 ChgPrioTransTable[5]={0,1,3,4};//SOL=>01, SOL+UTL=>03,ONLYSOL=>04,//1:Solar First;2:Solar+Utility; 3:Only Solar
 
    if(instruct->param2==0 ||(instruct->param2%2==1)){      
        return;//参数有误
    }
    
    if((instruct->param1+(instruct->param2>>1))>(ConfigParamMaxIndex+1)){
        return;//范问地址超过范围 
    }
    
    pParam=(u16*)instruct->data;
    for(Index= instruct->param1;Index<(instruct->param2>>1);Index++){
        switch(Index)
        {
            case Index_OutputPriority:        inverterParam1.output_src_prio=pParam[Index-instruct->param1]; break;
            case Index_MaxChargeCurrentAll:                   
                SysParam.EEMaxChgCurr=pParam[Index-instruct->param1]; 
                
                break;
            case Index_ACInVoltRange:         inverterParam1.ac_input_volt_range=pParam[Index-instruct->param1]; break;
            case Index_BatCapacity:           
                SysParam.BatCapacity=pParam[Index-instruct->param1]; 
                
                break;
            case Index_BatteryType:           inverterParam1.batteryType=BatTypeIndex[pParam[Index-instruct->param1]]; break;
            case Index_OverloadRestart:       inverterParam1.configWord.bits.overload_restart=pParam[Index-instruct->param1]; break;
            case Index_HighTemperatureRestart:inverterParam1.configWord.bits.overtemp_restart=pParam[Index-instruct->param1]; break;
            case Index_OutputVoltage:         inverterParam1.output_voltage=pParam[Index-instruct->param1]*10; break;
            case Index_OutputFrequency:       inverterParam1.output_frequency=pParam[Index-instruct->param1]*10; break;
            case Index_Master_Slave:          inverterParam1.configWord1.bits.parallelMaster=pParam[Index-instruct->param1]; break;
            case Index_MaxChargeCityCurrent:  
                SysParam.EEMaxUtlChgCurr=pParam[Index-instruct->param1]; 
                
                break;
            case Index_LowVoltReturnCityPower:inverterParam1.volt_point_2_utl=pParam[Index-instruct->param1]; break;//��ѹת��
            case Index_HighVoltReturnBattery: inverterParam1.volt_point_2_bat=pParam[Index-instruct->param1]; break;//��ѹת��
            case Index_BatteryChargePriority: inverterParam1.chg_src_prio=ChgPrioTransTable[pParam[Index-instruct->param1]] ; break;
            case Index_AlarmControl:          inverterParam1.configWord1.bits.alarm_control=pParam[Index-instruct->param1]; break; 
            case Index_BackLightCtrl:         
                SysParam.BacklightEn=pParam[Index-instruct->param1]; 
                
                break;             
            case Index_PowerShutdownAlarm:    inverterParam1.configWord.bits.pri_src_intr_alarm=pParam[Index-instruct->param1]; break;
            case Index_OverloadUseCityPower:  inverterParam1.configWord.bits.overload_bypass=pParam[Index-instruct->param1]; break;    
            case Index_ParaMaxDisChgCurr:     
                SysParam.ParaMaxDisChgCurr=pParam[Index-instruct->param1]; 
                            
                break;//并机系统最大放电电流
            case Index_ParaMaxChgCurr:        
                SysParam.ParaMaxChgCurr=pParam[Index-instruct->param1]; 
                       
                break;//并机系统最大充电电流   
//            case Index_RecoverThresholdVolt: 
//                SysParam.VCutoffRecvDiff=pParam[Index-instruct->param1]; 
//                
//                break;
            case Index_SolarPowerBalance:     
								inverterParam1.configWord.bits.solar_power_balance=pParam[Index-instruct->param1]; 
								break;
            case Index_ACOutputMode:          
								inverterParam1.parallelSetting=pParam[Index-instruct->param1]; 
								break;
            case Index_LiBatMaterial:
                SysParam.BatMaterial=pParam[Index-instruct->param1]; 
                
                break;
            case Index_CellInSerial_LiFePO4:  
                SysParam.BatSerial_LiFePO4=pParam[Index-instruct->param1]; 
                           
                break;
            case Index_CellInSerial_Li_NMC:   
                SysParam.BatSerial_LiNMC=pParam[Index-instruct->param1]; 
                
                break; 
            case Index_EqEnable:           
								inverterParam1.configWord.bits.equalization_enable=pParam[Index-instruct->param1]; 
								break;
            case Index_EqVoltageSet:       
								inverterParam1.equalization_voltage=pParam[Index-instruct->param1]>>2; 
								break;
            case Index_EqTimeSet:          
								inverterParam1.equalized_time=pParam[Index-instruct->param1]; 
								break;
            case Index_EqtTimeoutSet:      
								inverterParam1.equalized_timeout=pParam[Index-instruct->param1]; 
								break;
            case Index_EqtIntervalSet:     
								inverterParam1.equalized_interval=pParam[Index-instruct->param1]; 
								break;
            case Index_EqactivateSet:      
                SysParam.EqactivateSet=pParam[Index-instruct->param1]; 
                
                break;   
            case Index_ChargeTimeSet:      
								inverterParam1.utilityChargingTime=pParam[Index-instruct->param1]>>8; 
								break;
            case Index_CloseChargeTimeSet: 
								inverterParam1.utilityChargingTime1=pParam[Index-instruct->param1]>>8; 
								break;
            case Index_LVoltOpenGenerator: 
                SysParam.GeStartVoltage=pParam[Index-instruct->param1]/10; 
                
                break;
            case Index_HVoltCloseGenerator: 
                SysParam.GeStopVoltage=pParam[Index-instruct->param1]/10; 
                
                break;
            case Index_SocBackUtl:         
								inverterParam1.soc_point_2_utl=pParam[Index-instruct->param1]; 
								break;
            case Index_SocBackBat:         
								inverterParam1.soc_point_2_bat=pParam[Index-instruct->param1]; 
								break;
            case Index_SocBackGen:         
                SysParam.GeStartSOC=pParam[Index-instruct->param1]; 
                
                break;
            case Index_SocCloseGen:
                SysParam.GeStopSOC=pParam[Index-instruct->param1]; 
                
                break;
            case Index_Soccutoff:          
							  inverterParam1.cutoff_soc=pParam[Index-instruct->param1]; 
								break;   
            case Index_BuzzerEN:           
                SysParam.BuzzerEn=pParam[Index-instruct->param1];
                
                break;  
			case Index_S_GradeSOC:
//				smartSwitch.TempSLevelSOCThres=pParam[Index-instruct->param1]; 
//				SettingSSOCFlag = 1;
			    break;
            case Index_A_GradeSOC:
//				smartSwitch.TempALevelSOCThres=pParam[Index-instruct->param1]; 
//				SettingASOCFlag = 1;
			    break;
            case Index_B_GradeSOC:
//				smartSwitch.TempBLevelSOCThres=pParam[Index-instruct->param1]; 
//				SettingBSOCFlag = 1;
			    break;
            case Index_ManualSocket:
//				SettingManualSocketFlag = 1;
//				smartSwitch.TempManualSocket = pParam[Index-instruct->param1]; 
			    break;
            case Index_ControlSocket:              
//				SettingControlSocketFlag = 1;
//				smartSwitch.ControlSocket = pParam[Index-instruct->param1];
			    break;			
//            case Index_RecoverThresholdSoc:        
//                SysParam.SocCutoffRecvDiff =pParam[Index-instruct->param1]; 
//                 
//                break;
            case Index_LiBatProtocolType:   inverterParam1.configWord1.bits.RS485Protocol=pParam[Index-instruct->param1]; break;
            case Index_GenRateWatt:         
                SysParam.GeRatedPower=pParam[Index-instruct->param1]; 
                
                break;
            case Index_GeBalanceEn:         
                SysParam.GeBalanceEn=pParam[Index-instruct->param1]; 
                
                break;            
            case Index_GenWorkStartTime1L:  
                SysParam.GenWorkStartTime1=pParam[Index-instruct->param1];             
                break;             
            case Index_GenWorkStartTime1H:  
                SysParam.GenWorkStartTime1|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_GenWorkEndTime1L:    
                SysParam.GenWorkEndTime1=pParam[Index-instruct->param1]; 
                break;
            case Index_GenWorkEndTime1H:                   
                SysParam.GenWorkEndTime1|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_GenWorkStartTime2L:  
                SysParam.GenWorkStartTime2=pParam[Index-instruct->param1];             
                break;              
            case Index_GenWorkStartTime2H:  
                SysParam.GenWorkStartTime2|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_GenWorkEndTime2L:    
                SysParam.GenWorkEndTime2=pParam[Index-instruct->param1]; 
                break;
            case Index_GenWorkEndTime2H:                   
                SysParam.GenWorkEndTime2|=pParam[Index-instruct->param1]<<16; 
                
            break;
            case Index_UtiOutputStartTime1L:
                SysParam.UtiOutputStartTime1=pParam[Index-instruct->param1];             
                break;
            case Index_UtiOutputStartTime1H:
                SysParam.UtiOutputStartTime1|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_UtiOutputEndTime1L:  
                SysParam.UtiOutputEndTime1=pParam[Index-instruct->param1];  
                break;
            case Index_UtiOutputEndTime1H: 
                SysParam.UtiOutputEndTime1|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_UtiOutputStartTime2L:
                SysParam.UtiOutputStartTime2=pParam[Index-instruct->param1];             
                break;
            case Index_UtiOutputStartTime2H:
                SysParam.UtiOutputStartTime2|=pParam[Index-instruct->param1]<<16; 
                
                break;
            case Index_UtiOutputEndTime2L:  
                SysParam.UtiOutputEndTime2=pParam[Index-instruct->param1];  
                break;
            case Index_UtiOutputEndTime2H: 
                SysParam.UtiOutputEndTime2|=pParam[Index-instruct->param1]<<16; 
                
                break;  
            case Index_VbatAgm:         
                SysParam.EEBatAgmVbat=pParam[Index-instruct->param1]>>2; 
                
                break;
            case Index_VbatFlood:       
                SysParam.EEBatFloodVbat=pParam[Index-instruct->param1]>>2; 
                
                break;  						
            case Index_VbatUserPb:      
                SysParam.EEBatUserPbVbat=pParam[Index-instruct->param1]>>2; 
                
                break;
            case Index_VbatAgmFloat:        
                SysParam.EEBatAgmVfloat=pParam[Index-instruct->param1]>>2; 
                
                break;
            case Index_VbatFloodFloat:      
                SysParam.EEBatFloodVfloat=pParam[Index-instruct->param1]>>2; 
                
                break;
            case Index_VbatLiFloat:         
                SysParam.EEBatLiVfloat=pParam[Index-instruct->param1]>>2; 
                
                break;
            case Index_VbatUserPbFloat:     
                SysParam.EEBatUserPbVfloat=pParam[Index-instruct->param1]>>2; 
                
                break;  
            case Index_VbatUserLiFeFloat:   
                SysParam.EEBatUserLiFeVfloat=(pParam[Index-instruct->param1]*SysParam.BatSerial_LiFePO4+2)>>2; 
                
                break;
            case Index_VbatUserLiNmcFloat:  
                SysParam.EEBatUserLiNMCVfloat=(pParam[Index-instruct->param1]*SysParam.BatSerial_LiNMC+2)>>2; 
                
                break;
            case Index_VbatAgmCutOff:       
                SysParam.EEBatAgmVcutoff=pParam[Index-instruct->param1]>>2; 
                
                break;  
            case Index_VbatFloodCutOff:                 
                SysParam.EEBatFloodVcutoff=pParam[Index-instruct->param1]>>2;
                
                break;
            case Index_VbatLiCutOff:        
                SysParam.EEBatLiVcutoff=pParam[Index-instruct->param1]>>2; 
                                  
                break;
            case Index_VbatUserPbCutOff:    
                SysParam.EEBatUserPbVcutoff=pParam[Index-instruct->param1]>>2; 
                 
                break;
            case Index_VbatUserLiFeCutOff:  
                SysParam.EEBatUserLiFeVcutoff=(pParam[Index-instruct->param1]*SysParam.BatSerial_LiFePO4+2)>>2; 
                 
                break;
            case Index_VbatUserLiNmcCutOff: 
                SysParam.EEBatUserLiNMCVcutoff=(pParam[Index-instruct->param1]*SysParam.BatSerial_LiNMC+2)>>2; 
                 
                break;             
            case Index_SocMaxUtlChg:        
                SysParam.SocMaxUtlChg=pParam[Index-instruct->param1]; 
                
                break; 
            case Index_VMaxUtlChg:          
                SysParam.VMaxUtlChg=pParam[Index-instruct->param1]/10; 
                
                break;           
        }
    }
    
		L00B8DC_flash();//修改非法参数值

    extern void update_dsp_parameter(void);
    //保存inverterParam1到Flash滚动区并通知DSP
    if(ParamFlash_Append((u8*)&inverterParam1, PARAM_RECORD_SIZE)){
        err=1;
    }
    SysParamFlash_SavePersist();                    //保存SysParam到Flash
    if(!err){
        update_dsp_parameter();                     //通知DSP同步参数
    }
    

////执行返回////////////////////////////////////////////////   
    u32 TempKey[4],crc32;
    
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    
    instruct->CmdLen=12;
    instruct->param1=0;
    instruct->param2=1;
    _memset(instruct->data,0,20);    
    instruct->data[0]=err;
    crc32=CRC32_HW((u32*)instruct,0xFFFFFFFF,instruct->CmdLen>>2);
    instruct->data[4]=crc32;    
    instruct->data[5]=crc32>>8;
    instruct->data[6]=crc32>>16;
    instruct->data[7]=crc32>>24;    
    EncryptData((u8*)instruct, TempKey,16);
    
    _memcpy(&instruct->data[8],&TempKey[2],8);
    EncryptData((u8*)instruct, FrameKey,24);     
    PppSend((u8*)instruct,24);
}



u8 updateInverterParam(inverterParam_t*pInverterParam)
{
    extern void update_dsp_parameter(void);
    u8 temp,err,buf[0xA2];

    _memcpy(buf,(u8 *)pInverterParam,0xA2);
    for(u16 i=0;i<0xA2;i+=2)
    {
        temp = buf[i+1];
        buf[i+1] = buf[i];
        buf[i] = temp;
    }
    
    err=0;
    if(EepromWriteData(0, buf, 0xA2)){        
        err=1;
    }
    
    if(!err){
        update_dsp_parameter();
    }
    return err;
}


void ReadCanReadWriteData(CollectorCmdDef *instruct)
{
    u8 *pmemaddr;
    u16 EncryptLen;
    CollectorCmdDef *pInstruct;
    u32 crc32,pReadWiteDataoffset,pInstructoffset;
    u32 TempKey[4];
    ReadWiteData_Def *pReadWiteData;
    
    pmemaddr=(u8*)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pReadWiteDataoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pReadWiteDataoffset;        
    }else{
        pReadWiteDataoffset=0;
    }
    pReadWiteData=(ReadWiteData_Def *)pmemaddr;
    
    
    if(instruct->param2==0 ||(instruct->param2%2==1)){
        free(((u8*)pReadWiteData)-pReadWiteDataoffset);       
        return;//参数有误
    }
    
    if(instruct->param1<ReadWiteDataStartIndex  || (instruct->param1+(instruct->param2>>1)) >(ReadWiteDataEndIndex+1)){
        free(((u8*)pReadWiteData)-pReadWiteDataoffset);
        return;//范问地址超过范围 
    }        
        
    pReadWiteData->CtrlParamAlterTime=ReadCtrlParamAlterTime();   

////////////////////////////////////////////////////////////////////////////////////////    
    pmemaddr=(u8 *)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pInstructoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pInstructoffset;        
    }else{
        pInstructoffset=0;
    }
    pInstruct=(CollectorCmdDef *)pmemaddr;
    
    _memset((u8*)pInstruct,0,256-pInstructoffset);
    pInstruct->header=instruct->header;
    pInstruct->cmd=instruct->cmd;
    pInstruct->CmdLen=((instruct->param2+8+3)>>2)<<2;//长度必须为4的整数倍
    pInstruct->param1=instruct->param1;
    pInstruct->param2=instruct->param2;
    
    u16 *ReadWiteData=(u16*)pReadWiteData;
    _memcpy(pInstruct->data,&ReadWiteData[(instruct->param1-ReadWiteDataStartIndex)>>1],instruct->param2);
    free(((u8*)pReadWiteData)-pReadWiteDataoffset);
    
    crc32=CRC32_HW((u32*)pInstruct,0xFFFFFFFF,pInstruct->CmdLen>>2);

    pInstruct->data[pInstruct->CmdLen-8]=crc32;    
    pInstruct->data[pInstruct->CmdLen-7]=crc32>>8;
    pInstruct->data[pInstruct->CmdLen-6]=crc32>>16;
    pInstruct->data[pInstruct->CmdLen-5]=crc32>>24;
    EncryptLen=((pInstruct->CmdLen+4+7)>>3)<<3;
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    EncryptData((u8*)pInstruct, TempKey,EncryptLen);
    _memcpy(((u8*)pInstruct)+EncryptLen,&TempKey[2],8);
    EncryptLen+=8;
    EncryptData((u8*)pInstruct, FrameKey,EncryptLen);     
    PppSend((u8*)pInstruct,EncryptLen);
    
    free(((u8*)pInstruct)-pInstructoffset);
        
}

void WriteCanReadWriteData(CollectorCmdDef *instruct)
{
    u8 err=0;
    u16 Index,*pParam;
    u32 temp,Time,rtc;
    s8 TimeZone;
    DATETIME DateTime;
    
    if(instruct->param2==0 ||(instruct->param2%2==1)){      
        return;//参数有误
    }
    
    if((instruct->param1+(instruct->param2>>1))>(CanReadWriteDataMaxIndex+1)){
        return;//范问地址超过范围
    }
    
    pParam=(u16*)instruct->data;
    for(Index=instruct->param1;Index<(instruct->param1+(instruct->param2>>1));Index++){
        switch(Index)
        {
            case Index_CtrlParamAlterTimeL: 
                temp=0;                
                temp=pParam[Index-instruct->param1];
            break;
            
            case Index_CtrlParamAlterTimeH:                                
                temp|=(pParam[Index-instruct->param1]<<8);
                //CtrlParamAlterTimeSet(temp,0);
            break;  

            case Index_UTCL:
                rtc=0;                
                rtc=pParam[Index-instruct->param1];
            break;

            case Index_UTCH:
                rtc|=(pParam[Index-instruct->param1]<<16);
                Time=TimeToSeconds(&SystemTime);
                TimeZone=SysParam.TimeZone;
                //UTCתRTC
                if(TimeZone>0){
                    rtc=rtc+TimeZone*3600;
                }else if(TimeZone<0){
                    TimeZone=(~TimeZone)+1;
                    rtc=rtc-TimeZone*3600;
                }                   
                if((Time>rtc?(Time-rtc):(rtc-Time))>4){//如果时间相差大于4s就重新设置                      
                    SecondsToTime(rtc,&DateTime);
                    SetTime(DateTime);
                }
            break;            
        }    
    }
    
////执行返回////////////////////////////////////////////////   
    u32 TempKey[4],crc32;
    
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    
    instruct->CmdLen=12;
    _memset(instruct->data,0,20);    
    instruct->data[0]=err;
    crc32=CRC32_HW((u32*)instruct,0xFFFFFFFF,instruct->CmdLen>>2);
    instruct->data[4]=crc32;    
    instruct->data[5]=crc32>>8;
    instruct->data[6]=crc32>>16;
    instruct->data[7]=crc32>>24;    
    EncryptData((u8*)instruct, TempKey,16);
    
    _memcpy(&instruct->data[8],&TempKey[2],8);
    EncryptData((u8*)instruct, FrameKey,24);     
    PppSend((u8*)instruct,24);      
}

extern char Firmware[18];
extern char SerialNumber[17];
void ReadOnlyReadData(CollectorCmdDef *instruct)
{
    u8 *pmemaddr;
    u16 EncryptLen;
    CollectorCmdDef *pInstruct;
    u32 crc32,pOnlyReadoffset,pInstructoffset;
    u32 TempKey[4];
    OnlyReadData_Def *pOnlyReadData;
    
    pmemaddr=(u8*)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pOnlyReadoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pOnlyReadoffset;        
    }else{
        pOnlyReadoffset=0;
    }
    pOnlyReadData=(OnlyReadData_Def *)pmemaddr;
    
    
    if(instruct->param2==0 ||(instruct->param2%2==1)){
        free(((u8*)pOnlyReadData)-pOnlyReadoffset);       
        return;//参数有误
    }
    
    if(instruct->param1<OnlyReadDataStartIndex  || (instruct->param1+(instruct->param2>>1)) >(OnlyReadDataEndIndex+1)){
        free(((u8*)pOnlyReadData)-pOnlyReadoffset);
        return;//范问地址超过范围 
    }
        
   // pOnlyReadData->ARMFirmwareVersion=0x0103;
    pOnlyReadData->ARMFirmwareVersion=((Firmware[10]-0x30)<<8)+(Firmware[12]-0x30)*10+(Firmware[13]-0x30);
    if(SysParam.DSPVersion3==0x0b && SysParam.DSPVersion4==0x0e){
        pOnlyReadData->DSPFirmwareVersion=0x0102;
    }else{
        pOnlyReadData->DSPFirmwareVersion=0x0100;
    }
    
    pOnlyReadData->InverterModuleL=0x0102;
    pOnlyReadData->InverterModuleH=0x0102;
    pOnlyReadData->HardwareVersion=0x0000; 
    //"20-20-12011527"    
//    pOnlyReadData->Inverter_SN1=(SerialNumber[0]-0x30)|((SerialNumber[1]-0x30)<<4)|((SerialNumber[3]-0x30)<<8)|((SerialNumber[4]-0x30)<<12);
//    pOnlyReadData->Inverter_SN2=(SerialNumber[6]-0x30)|((SerialNumber[7]-0x30)<<4)|((SerialNumber[8]-0x30)<<8)|((SerialNumber[9]-0x30)<<12);
//    pOnlyReadData->Inverter_SN3=(SerialNumber[10]-0x30)|((SerialNumber[11]-0x30)<<4)|((SerialNumber[12]-0x30)<<8)|((SerialNumber[13]-0x30)<<12);
//    pOnlyReadData->Inverter_SN4=0xFFFF;
		pOnlyReadData->Inverter_SN1 = (u8)SerialNumber[0]  | ((u8)SerialNumber[1] << 8) | ((u8)SerialNumber[2] << 16) | ((u8)SerialNumber[3] << 24);  // 'H','1'
		pOnlyReadData->Inverter_SN2 = (u8)SerialNumber[4]  | ((u8)SerialNumber[5] << 8) | ((u8)SerialNumber[6] << 16) | ((u8)SerialNumber[7] << 24);  // 'Z','Z'
		pOnlyReadData->Inverter_SN3 = (u8)SerialNumber[8]  | ((u8)SerialNumber[9] << 8) | ((u8)SerialNumber[10] << 16) | ((u8)SerialNumber[11] << 24);  // 'X','0'
		pOnlyReadData->Inverter_SN4 = (u8)SerialNumber[12]  | ((u8)SerialNumber[13] << 8) | ((u8)SerialNumber[14] << 16) | ((u8)SerialNumber[15] << 24);  // '0','1'
//		pOnlyReadData->Inverter_SN5 = (u8)SerialNumber[8]  | ((u8)SerialNumber[9] << 8);  // '3','9'
//		pOnlyReadData->Inverter_SN6 = (u8)SerialNumber[10] | ((u8)SerialNumber[11] << 8); // '0','0'
//		pOnlyReadData->Inverter_SN7 = (u8)SerialNumber[12] | ((u8)SerialNumber[13] << 8); // '0','0'
//		pOnlyReadData->Inverter_SN8 = (u8)SerialNumber[14] | ((u8)SerialNumber[15] << 8); // '1','P'

    pOnlyReadData->DeviceTypeCodeL=0x0101;
    pOnlyReadData->DeviceTypeCodeH=0x0102;
    pOnlyReadData->RateWatt=5000;
    pOnlyReadData->RateVA  =5000;
    pOnlyReadData->NomGridVolt=240;
    pOnlyReadData->NomGridFreq=60;
    pOnlyReadData->NomBatVolt=60;
    pOnlyReadData->NomPvCurr=100;
    pOnlyReadData->NomAcChgCurr=80;
    pOnlyReadData->NomOpVolt=240;
    pOnlyReadData->NomOpFreq=60;
    pOnlyReadData->NomOpPow=5000;
    pOnlyReadData->BLVersion=0x0101;   

////////////////////////////////////////////////////////////////////////////////////////    
    pmemaddr=(u8 *)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pInstructoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pInstructoffset;        
    }else{
        pInstructoffset=0;
    }
    pInstruct=(CollectorCmdDef *)pmemaddr;
    
    _memset((u8*)pInstruct,0,256-pInstructoffset);
    pInstruct->header=instruct->header;
    pInstruct->cmd=instruct->cmd;
    pInstruct->CmdLen=((instruct->param2+8+3)>>2)<<2;//长度必须为4的整数倍
    pInstruct->param1=instruct->param1;
    pInstruct->param2=instruct->param2;
    
    u16 *ReadWiteData=(u16*)pOnlyReadData;
    _memcpy(pInstruct->data,&ReadWiteData[(instruct->param1-OnlyReadDataStartIndex)>>1],instruct->param2);
    free(((u8*)pOnlyReadData)-pOnlyReadoffset);
    
    crc32=CRC32_HW((u32*)pInstruct,0xFFFFFFFF,pInstruct->CmdLen>>2);

    pInstruct->data[pInstruct->CmdLen-8]=crc32;    
    pInstruct->data[pInstruct->CmdLen-7]=crc32>>8;
    pInstruct->data[pInstruct->CmdLen-6]=crc32>>16;
    pInstruct->data[pInstruct->CmdLen-5]=crc32>>24;
    EncryptLen=((pInstruct->CmdLen+4+7)>>3)<<3;
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    EncryptData((u8*)pInstruct, TempKey,EncryptLen);
    _memcpy(((u8*)pInstruct)+EncryptLen,&TempKey[2],8);
    EncryptLen+=8;
    EncryptData((u8*)pInstruct, FrameKey,EncryptLen);     
    PppSend((u8*)pInstruct,EncryptLen);
    
    free(((u8*)pInstruct)-pInstructoffset);      
}

void ReadTestRunParam(CollectorCmdDef *instruct)
{
    u8 *pmemaddr;
    u16 EncryptLen;
    CollectorCmdDef *pInstruct;
    u32 crc32,pRunParamoffset,pInstructoffset;
    u32 TempKey[4];
    TestRunParamDef *pRunParam;
    
    pmemaddr=(u8*)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pRunParamoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pRunParamoffset;        
    }else {
        pRunParamoffset=0;
    }
    pRunParam=(TestRunParamDef *)pmemaddr;
    
    
    if(instruct->param2==0 || (instruct->param1%2)==1||(instruct->param2%2==1)){
        free(((u8*)pRunParam)-pRunParamoffset);       
        return;//参数有误
    }
    
    if((instruct->param1+(instruct->param2>>1)) >((sizeof(TestRunParamDef)>>1)+1)){
        free(((u8*)pRunParam)-pRunParamoffset);
        return;//范问地址超过范围 
    }
    
	
    pRunParam->SysStatus=0;
	if(SwitchDetect()==0) {
		pRunParam->SysStatusBits.StandBy =1; 
	} 
	
	if(SysParam.errorCode!=0 || ArmDspComm.tick==0) {
		pRunParam->SysStatusBits.Fault = 1 ;
	}
	// UIStatus.Bit.BatStatus=0;//0:�޵��;1���ڳ��;2:�ڷŵ�;3:�е�����޳��ͷŵ�
    if(UIStatus.Bit.BatStatus==1){
        pRunParam->SysStatusBits.Charge=1;
    }else if(UIStatus.Bit.BatStatus==2) {
		pRunParam->SysStatusBits.Discharging = 1;
	}

    if(UIStatus.Bit.PvStatus==1){
        pRunParam->SysStatusBits.Pvinput=1;
    }else if(UIStatus.Bit.PvStatus==2) {
		pRunParam->SysStatusBits.PVCharging = 1;
        pRunParam->SysStatusBits.Pvinput=1;
	} 
	
	if(UIStatus.Bit.UtStatus && UIStatus.Bit.UtCharge) {
		pRunParam->SysStatusBits.ACCharging = 1;
	}else if(UIStatus.Bit.UtStatus&& UIStatus.Bit.GeStatus==0){
        pRunParam->SysStatusBits.AcInput = 1;
    }
		
	if(UIStatus.Bit.GeStatus && UIStatus.Bit.UtCharge) {
		pRunParam->SysStatusBits.GenCharging = 1;
	}else if(UIStatus.Bit.GeStatus){
        pRunParam->SysStatusBits.GeInput= 1;
    }
	
//	if(SysParam.inverter_status.ACOutput && SysParam.inverter_status.ACBypass) {
//		pRunParam->SysStatusBits.ACBypass = 1;
//	}
	  if(SysParam.inverter_status.RelayAcL)		pRunParam->SysStatusBits.ACBypass = 1;
		
    if(UIStatus.Bit.ACOutStatus){
        pRunParam->SysStatusBits.ToLoad=1;
    }    
    
		pRunParam->Vpv1=SysParam.Vpv1;
		pRunParam->Vpv2=SysParam.Vpv2;		
//    pRunParam->Ppv1=SysParam.Ppv1;
//		pRunParam->Ppv2=SysParam.Ppv2;
//		pRunParam->Ppv=SysParam.Ppv1+SysParam.Ppv2;;		
    pRunParam->OutputWatt=SysParam.Pload;
    pRunParam->OutputVA=SysParam.Sload;
    pRunParam->OutputCurr=SysParam.IloadA;
    pRunParam->ACChrWatt=SysParam.Pgrid;
    pRunParam->ACChrVA=SysParam.Pgrid;//��VA����
    pRunParam->GridVolt=SysParam.VgridA;
    pRunParam->GridFreq=SysParam.GridFreq;
    pRunParam->ACOutputVolt=SysParam.VgridA;
    pRunParam->ACOutputFreq=SysParam.GridFreq;
    pRunParam->ACInWatt=SysParam.Pgrid;
    pRunParam->ACInVA=SysParam.Sgrid;//��VA
    pRunParam->ACDisChrWatt=SysParam.Pgrid;
    pRunParam->ACDisChrVA=SysParam.Sgrid;
    pRunParam->ACChrCurr=SysParam.IgridA;
    pRunParam->BatVolt=SysParam.VbatA*10;
    pRunParam->BatterySOC=SysParam.BatPercent;
    if(pRunParam->BatterySOC>100){
        pRunParam->BatterySOC=0;
    }
    pRunParam->BatDisChrWatt=SysParam.Ibat;
    pRunParam->BatChrWatt=SysParam.Pgrid;
    pRunParam->BatChgCurr=batChgCurr;
    pRunParam->BatDischgCurr=batDsgCurr;
    pRunParam->BatOverCharge=SysParam.warningCode2Bits.batOverCharged;
    pRunParam->BusVolt=SysParam.BusVoltage/10;

    pRunParam->LoadPercent=SysParam.LoadPercent;

	

					
    union{
        struct{
        u16 parallelNoBat:1,//������22,parallel fibidden without battery
			fan2Locked  :1,//������17 ,the invert fan is locked	
			ParaVerDiff      :1,//������18,parallel version different
			UnstableGridFrq  :1,//������19,grid frequency unstable
            reserved2:12;
        }bits;
        u16 word;   
    } tempWarningCode1;  //ת�������������Э����ͬ�Ķ���
	
//	tempWarningCode2.bits.parallelNoBat = SysParam.warningCode1Bits.parallelNoBat;
//	tempWarningCode1.bits.fan2Locked = SysParam.warningCode1Bits.fan2Locked | SysParam.warningCode1Bits.fan2Slow;
//	tempWarningCode1.bits.ParaVerDiff = SysParam.warningCode1Bits.ParaVerDiff;
//	tempWarningCode1.bits.UnstableGridFrq = SysParam.warningCode1Bits.UnstableGridFrq;
	
	u16 tempWarningCode = SysParam.warningCode;
	if(SysParam.warningCode1Bits.Fan1SpeedLow || SysParam.warningCode1Bits.Fan2SpeedLow) {
		tempWarningCode |= 0x1;
	} else {
		tempWarningCode &= 0xfffe;
	}
	
    pRunParam->Warning=(tempWarningCode1.word<<16)|tempWarningCode;
    pRunParam->BmsWarning=SysParam.warningCode2&0x1FFF;
    pRunParam->FaultValue=SysParam.errorCode;
    
    pRunParam->InvertTemp=Temperature_Struct.HV_IGBT*10;
    pRunParam->BoostTemp=Temperature_Struct.LV_MOS*10;
//    pRunParam->TransformerTemp=Temperature_Struct.Transformer*10;
//    pRunParam->PVTemp=Temperature_Struct.PV*10;
       
////////////////////////////////////////////////////////////////////////////////////////    
    pmemaddr=(u8 *)malloc(256);    
    if(!pmemaddr){
        return;
    }
    
    if((u32)pmemaddr%4){
        pInstructoffset=4-(((u32)pmemaddr)%4); 
        pmemaddr+=pInstructoffset;        
    }else{
        pInstructoffset=0;
    }
    pInstruct=(CollectorCmdDef *)pmemaddr;
    
    _memset((u8*)pInstruct,0,256-pInstructoffset);
    pInstruct->header=instruct->header;
    pInstruct->cmd=instruct->cmd;
    pInstruct->CmdLen=((instruct->param2+8+3)>>2)<<2;//���ȱ���Ϊ4��������
    pInstruct->param1=instruct->param1;
    pInstruct->param2=instruct->param2;
    
    u16 *RunParam=(u16*)pRunParam;
    _memcpy(pInstruct->data,&RunParam[(instruct->param1)>>1],instruct->param2);
    free(((u8*)pRunParam)-pRunParamoffset);
    
    crc32=CRC32_HW((u32*)pInstruct,0xFFFFFFFF,pInstruct->CmdLen>>2);

    pInstruct->data[pInstruct->CmdLen-8]=crc32;    
    pInstruct->data[pInstruct->CmdLen-7]=crc32>>8;
    pInstruct->data[pInstruct->CmdLen-6]=crc32>>16;
    pInstruct->data[pInstruct->CmdLen-5]=crc32>>24;
    EncryptLen=((pInstruct->CmdLen+4+7)>>3)<<3;
    _memcpy(TempKey,FrameKey,16);
    TempKey[3]=SysTick->VAL;
    TempKey[2]=~TempKey[3];
    EncryptData((u8*)pInstruct, TempKey,EncryptLen);
    _memcpy(((u8*)pInstruct)+EncryptLen,&TempKey[2],8);
    EncryptLen+=8;
    EncryptData((u8*)pInstruct, FrameKey,EncryptLen);     
    PppSend((u8*)pInstruct,EncryptLen);
    
    free(((u8*)pInstruct)-pInstructoffset);
}

