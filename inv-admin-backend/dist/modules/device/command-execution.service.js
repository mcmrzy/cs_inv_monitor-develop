"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var CommandExecutionService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.CommandExecutionService = exports.COMMAND_TEMPLATES = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const uuid_1 = require("uuid");
const command_log_entity_1 = require("../../entities/command-log.entity");
const device_server_proxy_service_1 = require("./device-server-proxy.service");
exports.COMMAND_TEMPLATES = [
    {
        name: 'set_active_power_limit',
        label: '设置有功功率限制',
        description: '限制逆变器输出有功功率百分比',
        category: 'power',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '功率限制百分比', type: 'number', required: true,
                min: 0, max: 100, defaultValue: 100, unit: '%',
            }],
    },
    {
        name: 'set_reactive_power',
        label: '设置无功功率',
        description: '设置无功功率输出值',
        category: 'power',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '无功功率', type: 'number', required: true,
                min: -100, max: 100, defaultValue: 0, unit: '%',
            }],
    },
    {
        name: 'set_power_factor',
        label: '设置功率因数',
        description: '设置输出功率因数',
        category: 'power',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '功率因数', type: 'number', required: true,
                min: -1, max: 1, defaultValue: 1, unit: '',
            }],
    },
    {
        name: 'set_charge_voltage_limit',
        label: '设置充电电压上限',
        description: '电池充电截止电压',
        category: 'battery',
        requiresConfirm: true,
        confirmationMessage: '修改充电电压可能影响电池寿命',
        params: [{
                name: 'value', label: '电压上限', type: 'number', required: true,
                min: 40, max: 60, defaultValue: 54.6, unit: 'V',
            }],
    },
    {
        name: 'set_discharge_voltage_limit',
        label: '设置放电电压下限',
        description: '电池放电截止电压',
        category: 'battery',
        requiresConfirm: true,
        confirmationMessage: '修改放电电压可能影响电池寿命',
        params: [{
                name: 'value', label: '电压下限', type: 'number', required: true,
                min: 40, max: 55, defaultValue: 44, unit: 'V',
            }],
    },
    {
        name: 'set_max_charge_current',
        label: '设置最大充电电流',
        description: '电池最大充电电流',
        category: 'battery',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '电流上限', type: 'number', required: true,
                min: 0, max: 200, defaultValue: 100, unit: 'A',
            }],
    },
    {
        name: 'set_max_discharge_current',
        label: '设置最大放电电流',
        description: '电池最大放电电流',
        category: 'battery',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '电流上限', type: 'number', required: true,
                min: 0, max: 200, defaultValue: 100, unit: 'A',
            }],
    },
    {
        name: 'set_work_mode',
        label: '设置工作模式',
        description: '更改逆变器运行模式',
        category: 'system',
        requiresConfirm: true,
        confirmationMessage: '切换工作模式将改变逆变器运行策略',
        params: [{
                name: 'value', label: '工作模式', type: 'select', required: true, defaultValue: 'self_use',
                options: [
                    { label: '自发自用', value: 'self_use' },
                    { label: '优先售电', value: 'sell_first' },
                    { label: '备用电源', value: 'backup' },
                    { label: '离网模式', value: 'off_grid' },
                ],
            }],
    },
    {
        name: 'set_battery_type',
        label: '设置电池类型',
        description: '配置连接的电池类型',
        category: 'battery',
        requiresConfirm: true,
        confirmationMessage: '电池类型变更后需重新校准',
        params: [{
                name: 'value', label: '电池类型', type: 'select', required: true, defaultValue: 'lithium',
                options: [
                    { label: '锂电池(LiFePO4)', value: 'lithium' },
                    { label: '铅酸电池', value: 'lead_acid' },
                    { label: '胶体电池', value: 'gel' },
                    { label: '用户自定义', value: 'custom' },
                ],
            }],
    },
    {
        name: 'set_generator_power',
        label: '设置发电机功率',
        description: '离网模式下发电机输入功率',
        category: 'power',
        requiresConfirm: false,
        params: [{
                name: 'value', label: '发电机功率', type: 'number', required: true,
                min: 0, max: 10000, defaultValue: 5000, unit: 'W',
            }],
    },
    {
        name: 'set_over_voltage_threshold',
        label: '设置过压保护阈值',
        description: '电网过压保护电压',
        category: 'grid',
        requiresConfirm: true,
        params: [{
                name: 'value', label: '过压阈值', type: 'number', required: true,
                min: 200, max: 300, defaultValue: 265, unit: 'V',
            }],
    },
    {
        name: 'set_under_voltage_threshold',
        label: '设置欠压保护阈值',
        description: '电网欠压保护电压',
        category: 'grid',
        requiresConfirm: true,
        params: [{
                name: 'value', label: '欠压阈值', type: 'number', required: true,
                min: 150, max: 220, defaultValue: 180, unit: 'V',
            }],
    },
    {
        name: 'set_over_freq_threshold',
        label: '设置过频保护阈值',
        description: '电网过频保护频率',
        category: 'grid',
        requiresConfirm: true,
        params: [{
                name: 'value', label: '过频阈值', type: 'number', required: true,
                min: 49, max: 52, defaultValue: 50.5, unit: 'Hz',
            }],
    },
    {
        name: 'set_under_freq_threshold',
        label: '设置欠频保护阈值',
        description: '电网欠频保护频率',
        category: 'grid',
        requiresConfirm: true,
        params: [{
                name: 'value', label: '欠频阈值', type: 'number', required: true,
                min: 47, max: 50, defaultValue: 47.5, unit: 'Hz',
            }],
    },
    {
        name: 'set_island_protection',
        label: '孤岛保护开关',
        description: '启用/禁用孤岛保护',
        category: 'grid',
        requiresConfirm: true,
        confirmationMessage: '关闭孤岛保护可能违反电网规定',
        params: [{
                name: 'value', label: '孤岛保护', type: 'select', required: true, defaultValue: true,
                options: [
                    { label: '启用', value: true },
                    { label: '禁用', value: false },
                ],
            }],
    },
    {
        name: 'restart',
        label: '重启设备',
        description: '软重启逆变器',
        category: 'system',
        params: [],
        requiresConfirm: true,
        confirmationMessage: '重启期间设备将暂时离线约30秒',
    },
    {
        name: 'shutdown',
        label: '关机',
        description: '远程关闭逆变器',
        category: 'system',
        params: [],
        requiresConfirm: true,
        confirmationMessage: '关机后需现场重新启动设备',
    },
    {
        name: 'factory_reset',
        label: '恢复出厂设置',
        description: '将所有参数恢复至出厂默认值',
        category: 'system',
        params: [],
        requiresConfirm: true,
        confirmationMessage: '恢复出厂设置将清除所有自定义参数，且不可撤销！请输入设备SN后六位确认',
    },
    {
        name: 'set_charging_schedule',
        label: '设置充放电时段',
        description: '配置峰谷电价充放电策略',
        category: 'battery',
        requiresConfirm: false,
        params: [
            { name: 'charge_start', label: '充电开始时间(HH:MM)', type: 'string', required: true, defaultValue: '22:00' },
            { name: 'charge_end', label: '充电结束时间(HH:MM)', type: 'string', required: true, defaultValue: '06:00' },
        ],
    },
    {
        name: 'query_status',
        label: '查询状态',
        description: '立即查询设备当前运行状态',
        category: 'system',
        params: [],
        requiresConfirm: false,
    },
    {
        name: 'sync_time',
        label: '同步时间',
        description: '同步设备时钟到服务器时间',
        category: 'system',
        params: [],
        requiresConfirm: false,
    },
];
let CommandExecutionService = CommandExecutionService_1 = class CommandExecutionService {
    constructor(commandLogRepo, proxyService) {
        this.commandLogRepo = commandLogRepo;
        this.proxyService = proxyService;
        this.logger = new common_1.Logger(CommandExecutionService_1.name);
    }
    getCommandTemplates(sn) {
        return exports.COMMAND_TEMPLATES;
    }
    async executeCommand(sn, commandName, params, userId, ipAddress) {
        const template = exports.COMMAND_TEMPLATES.find((t) => t.name === commandName);
        if (!template) {
            throw new common_1.BadRequestException(`Unknown command: ${commandName}`);
        }
        this.validateParams(template, params);
        const reqId = (0, uuid_1.v4)();
        const commandLog = this.commandLogRepo.create({
            device_sn: sn,
            command_name: commandName,
            command_label: template.label,
            params: params || undefined,
            req_id: reqId,
            status: 'pending',
            executed_by: userId,
            ip_address: ipAddress || undefined,
            retry_count: 0,
        });
        await this.commandLogRepo.save(commandLog);
        try {
            commandLog.status = 'sent';
            await this.commandLogRepo.save(commandLog);
            await this.proxyService.sendCommand(sn, commandName, params || {}, reqId);
            let ackResult = null;
            try {
                ackResult = await this.proxyService.waitForAck(reqId, 12000);
            }
            catch (ackErr) {
                this.logger.warn(`ACK wait failed for ${reqId}: ${ackErr.message}`);
                if (ackErr.message?.includes('timeout')) {
                    commandLog.status = 'timeout';
                    commandLog.result_message = 'Device did not acknowledge command within timeout';
                    commandLog.completed_at = new Date();
                    await this.commandLogRepo.save(commandLog);
                    return {
                        success: false,
                        message: '指令发送成功但设备未在超时时间内响应',
                        reqId,
                        status: 'timeout',
                    };
                }
                commandLog.status = 'failed';
                commandLog.result_message = ackErr.message || 'ACK check failed';
                commandLog.completed_at = new Date();
                await this.commandLogRepo.save(commandLog);
                return {
                    success: false,
                    message: ackErr.message || '指令执行失败',
                    reqId,
                    status: 'failed',
                };
            }
            commandLog.status = ackResult?.status === 'ack_received' ? 'ack_received' : 'success';
            commandLog.result_message = 'Command executed successfully';
            commandLog.completed_at = new Date();
            await this.commandLogRepo.save(commandLog);
            return {
                success: true,
                message: '指令执行成功',
                reqId,
                status: commandLog.status,
            };
        }
        catch (err) {
            this.logger.error(`Command execution failed for ${sn}/${commandName}: ${err.message}`);
            commandLog.status = 'failed';
            commandLog.result_message = err.message || 'Unknown error';
            commandLog.completed_at = new Date();
            await this.commandLogRepo.save(commandLog);
            throw new common_1.HttpException(`指令执行失败: ${err.message}`, err.status || 500);
        }
    }
    async getCommandHistory(sn, page = 1, pageSize = 20) {
        const [items, total] = await this.commandLogRepo.findAndCount({
            where: { device_sn: sn },
            order: { created_at: 'DESC' },
            skip: (page - 1) * pageSize,
            take: pageSize,
        });
        return { items, total, page, pageSize };
    }
    validateParams(template, params) {
        if (!template.params || template.params.length === 0) {
            return;
        }
        for (const paramDef of template.params) {
            const value = params?.[paramDef.name];
            if (paramDef.required && (value === undefined || value === null || value === '')) {
                throw new common_1.BadRequestException(`参数 ${paramDef.label} (${paramDef.name}) 为必填项`);
            }
            if (value === undefined || value === null) {
                continue;
            }
            switch (paramDef.type) {
                case 'number': {
                    const num = Number(value);
                    if (isNaN(num)) {
                        throw new common_1.BadRequestException(`参数 ${paramDef.label} 必须是数字`);
                    }
                    if (paramDef.min !== undefined && num < paramDef.min) {
                        throw new common_1.BadRequestException(`参数 ${paramDef.label} 最小值为 ${paramDef.min}${paramDef.unit || ''}`);
                    }
                    if (paramDef.max !== undefined && num > paramDef.max) {
                        throw new common_1.BadRequestException(`参数 ${paramDef.label} 最大值为 ${paramDef.max}${paramDef.unit || ''}`);
                    }
                    break;
                }
                case 'select': {
                    if (paramDef.options && paramDef.options.length > 0) {
                        const validValues = paramDef.options.map((o) => o.value);
                        const valueToCheck = value;
                        const isValid = validValues.some((v) => String(v) === String(valueToCheck) || v === valueToCheck);
                        if (!isValid) {
                            throw new common_1.BadRequestException(`参数 ${paramDef.label} 的值无效，可选值为: ${paramDef.options.map((o) => o.label).join(', ')}`);
                        }
                    }
                    break;
                }
            }
        }
    }
};
exports.CommandExecutionService = CommandExecutionService;
exports.CommandExecutionService = CommandExecutionService = CommandExecutionService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(command_log_entity_1.CommandLog)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        device_server_proxy_service_1.DeviceServerProxyService])
], CommandExecutionService);
//# sourceMappingURL=command-execution.service.js.map