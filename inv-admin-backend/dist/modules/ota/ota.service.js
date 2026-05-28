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
Object.defineProperty(exports, "__esModule", { value: true });
exports.OtaService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const uuid_1 = require("uuid");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const http = require("http");
const firmware_entity_1 = require("../../entities/firmware.entity");
const ota_task_entity_1 = require("../../entities/ota-task.entity");
const ota_task_device_entity_1 = require("../../entities/ota-task-device.entity");
const device_entity_1 = require("../../entities/device.entity");
const UPLOAD_DIR = path.resolve(process.cwd(), 'uploads', 'firmware');
function sendMqttCommand(deviceSn, command, payload) {
    return new Promise((resolve, reject) => {
        const body = JSON.stringify({ command, payload });
        const url = `/admin/api/devices/${deviceSn}/command`;
        const options = {
            hostname: 'localhost',
            port: 8080,
            path: url,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body),
            },
        };
        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => resolve(data));
        });
        req.on('error', (err) => reject(err));
        req.write(body);
        req.end();
    });
}
let OtaService = class OtaService {
    constructor(firmwareRepo, otaTaskRepo, otaTaskDeviceRepo, deviceRepo) {
        this.firmwareRepo = firmwareRepo;
        this.otaTaskRepo = otaTaskRepo;
        this.otaTaskDeviceRepo = otaTaskDeviceRepo;
        this.deviceRepo = deviceRepo;
    }
    async uploadFirmware(file, dto, userId) {
        const modelDir = path.join(UPLOAD_DIR, dto.model, dto.version);
        if (!fs.existsSync(modelDir)) {
            fs.mkdirSync(modelDir, { recursive: true });
        }
        const destPath = path.join(modelDir, file.originalname);
        if (file.buffer) {
            fs.writeFileSync(destPath, file.buffer);
        }
        else if (file.path) {
            fs.copyFileSync(file.path, destPath);
        }
        const fileBuffer = file.buffer ?? fs.readFileSync(destPath);
        const sha256 = crypto.createHash('sha256').update(fileBuffer).digest('hex');
        const md5 = crypto.createHash('md5').update(fileBuffer).digest('hex');
        const relativeUrl = path.join('uploads', 'firmware', dto.model, dto.version, file.originalname).replace(/\\/g, '/');
        const firmware = this.firmwareRepo.create({
            model: dto.model,
            version: dto.version,
            file_url: relativeUrl,
            file_size: file.size,
            file_md5: md5,
            file_sha256: sha256,
            changelog: dto.changelog,
            is_force: dto.isForce ?? false,
            uploaded_by: userId,
            status: 1,
        });
        return this.firmwareRepo.save(firmware);
    }
    async getFirmwares(query) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const where = {};
        if (query.model) {
            where.model = query.model;
        }
        const [items, total] = await this.firmwareRepo.findAndCount({
            where,
            skip,
            take: pageSize,
            order: { created_at: 'DESC' },
        });
        return { items, total, page, pageSize };
    }
    async deleteFirmware(id) {
        const firmware = await this.firmwareRepo.findOne({ where: { id } });
        if (!firmware) {
            throw new common_1.NotFoundException('Firmware not found');
        }
        await this.firmwareRepo.remove(firmware);
    }
    async createTask(dto, userId) {
        const firmware = await this.firmwareRepo.findOne({ where: { id: dto.firmwareId } });
        if (!firmware) {
            throw new common_1.NotFoundException('Firmware not found');
        }
        const devices = await this.deviceRepo.find({
            where: { sn: (0, typeorm_2.In)(dto.deviceSns) },
        });
        if (devices.length !== dto.deviceSns.length) {
            const foundSns = devices.map((d) => d.sn);
            const missing = dto.deviceSns.filter((sn) => !foundSns.includes(sn));
            throw new common_1.BadRequestException(`Devices not found: ${missing.join(', ')}`);
        }
        const taskId = (0, uuid_1.v4)();
        const task = this.otaTaskRepo.create({
            id: taskId,
            name: dto.name,
            firmware_id: firmware.id,
            created_by: userId,
            status: ota_task_entity_1.OtaTaskStatus.PENDING,
            total_devices: dto.deviceSns.length,
            success_count: 0,
            failed_count: 0,
            push_strategy: dto.pushStrategy ?? 'all_at_once',
            push_percentage: dto.pushPercentage ?? 100,
            batch_size: dto.batchSize ?? 10,
        });
        await this.otaTaskRepo.save(task);
        const taskDevices = dto.deviceSns.map((sn) => {
            const device = devices.find((d) => d.sn === sn);
            return this.otaTaskDeviceRepo.create({
                task_id: taskId,
                device_sn: sn,
                old_version: device?.firmware_version,
                new_version: firmware.version,
                status: ota_task_device_entity_1.OtaTaskDeviceStatus.PENDING,
                progress: 0,
            });
        });
        await this.otaTaskDeviceRepo.save(taskDevices);
        return task;
    }
    async getTasks(query, currentUser) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const where = {};
        if (query.status) {
            where.status = query.status;
        }
        const [items, total] = await this.otaTaskRepo.findAndCount({
            where,
            skip,
            take: pageSize,
            order: { created_at: 'DESC' },
        });
        return { items, total, page, pageSize };
    }
    async getTaskDetail(taskId) {
        const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
        if (!task) {
            throw new common_1.NotFoundException('OTA Task not found');
        }
        return task;
    }
    async getTaskDevices(taskId, query) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const [items, total] = await this.otaTaskDeviceRepo.findAndCount({
            where: { task_id: taskId },
            skip,
            take: pageSize,
            order: { created_at: 'ASC' },
        });
        return { items, total, page, pageSize };
    }
    async executeTask(taskId) {
        const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
        if (!task) {
            throw new common_1.NotFoundException('OTA Task not found');
        }
        if (task.status !== ota_task_entity_1.OtaTaskStatus.PENDING) {
            throw new common_1.BadRequestException('Task can only be executed from pending status');
        }
        task.status = ota_task_entity_1.OtaTaskStatus.PUSHING;
        await this.otaTaskRepo.save(task);
        this.runExecutionStrategy(task).catch((err) => {
            console.error(`[OTA] Task ${taskId} execution error:`, err);
        });
        return task;
    }
    async runExecutionStrategy(task) {
        const taskId = task.id;
        const strategy = task.push_strategy || 'all_at_once';
        const percentage = task.push_percentage || 100;
        const batchSize = task.batch_size || 10;
        const allPendingDevices = await this.otaTaskDeviceRepo.find({
            where: { task_id: taskId, status: ota_task_device_entity_1.OtaTaskDeviceStatus.PENDING },
        });
        if (allPendingDevices.length === 0)
            return;
        let devicesToPush;
        if (strategy === 'percentage') {
            const count = Math.max(1, Math.floor(allPendingDevices.length * percentage / 100));
            const shuffled = [...allPendingDevices].sort(() => Math.random() - 0.5);
            devicesToPush = shuffled.slice(0, count);
        }
        else {
            devicesToPush = allPendingDevices;
        }
        if (strategy === 'batch') {
            await this.pushInBatches(taskId, devicesToPush, batchSize);
        }
        else {
            await this.pushAllAtOnce(taskId, devicesToPush);
        }
    }
    async pushAllAtOnce(taskId, devices) {
        const firmware = await this.firmwareRepo.findOne({
            where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } })).firmware_id },
        });
        const downloadUrl = firmware
            ? `http://${process.env.SERVER_HOST || 'localhost'}:${process.env.PORT || 3000}/static/${firmware.file_url}`
            : '';
        for (const td of devices) {
            try {
                const mqttPayload = {
                    task_id: taskId,
                    firmware_url: downloadUrl,
                    version: td.new_version,
                    md5: firmware?.file_md5,
                    sha256: firmware?.file_sha256,
                    file_size: firmware?.file_size,
                };
                td.mqtt_message = JSON.stringify(mqttPayload);
                td.status = ota_task_device_entity_1.OtaTaskDeviceStatus.DOWNLOADING;
                td.started_at = new Date();
                await this.otaTaskDeviceRepo.save(td);
                await sendMqttCommand(td.device_sn, 'ota_upgrade', mqttPayload);
            }
            catch (err) {
                td.status = ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED;
                td.error_message = err.message || 'MQTT push failed';
                td.completed_at = new Date();
                await this.otaTaskDeviceRepo.save(td);
            }
        }
        await this.updateTaskCounts(taskId);
    }
    async pushInBatches(taskId, devices, batchSize) {
        const firmware = await this.firmwareRepo.findOne({
            where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } })).firmware_id },
        });
        const downloadUrl = firmware
            ? `http://${process.env.SERVER_HOST || 'localhost'}:${process.env.PORT || 3000}/static/${firmware.file_url}`
            : '';
        for (let i = 0; i < devices.length; i += batchSize) {
            const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
            if (!task || task.status === ota_task_entity_1.OtaTaskStatus.CANCELLED)
                break;
            const batch = devices.slice(i, i + batchSize);
            for (const td of batch) {
                try {
                    const mqttPayload = {
                        task_id: taskId,
                        firmware_url: downloadUrl,
                        version: td.new_version,
                        md5: firmware?.file_md5,
                        sha256: firmware?.file_sha256,
                        file_size: firmware?.file_size,
                    };
                    td.mqtt_message = JSON.stringify(mqttPayload);
                    td.status = ota_task_device_entity_1.OtaTaskDeviceStatus.DOWNLOADING;
                    td.started_at = new Date();
                    await this.otaTaskDeviceRepo.save(td);
                    await sendMqttCommand(td.device_sn, 'ota_upgrade', mqttPayload);
                }
                catch (err) {
                    td.status = ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED;
                    td.error_message = err.message || 'MQTT push failed';
                    td.completed_at = new Date();
                    await this.otaTaskDeviceRepo.save(td);
                }
            }
            await this.updateTaskCounts(taskId);
            if (i + batchSize < devices.length) {
                await new Promise((resolve) => setTimeout(resolve, 30000));
            }
        }
    }
    async rollbackTask(taskId) {
        const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
        if (!task) {
            throw new common_1.NotFoundException('OTA Task not found');
        }
        if (task.status !== ota_task_entity_1.OtaTaskStatus.COMPLETED && task.status !== ota_task_entity_1.OtaTaskStatus.FAILED) {
            throw new common_1.BadRequestException('Only completed or failed tasks can be rolled back');
        }
        const successDevices = await this.otaTaskDeviceRepo.find({
            where: { task_id: taskId, status: ota_task_device_entity_1.OtaTaskDeviceStatus.SUCCESS },
        });
        if (successDevices.length === 0) {
            throw new common_1.BadRequestException('No successfully upgraded devices to roll back');
        }
        const firmware = await this.firmwareRepo.findOne({ where: { id: task.firmware_id } });
        for (const td of successDevices) {
            if (!td.old_version)
                continue;
            const rollbackPayload = {
                task_id: taskId,
                firmware_url: '',
                version: td.old_version,
                md5: '',
                sha256: '',
                rollback: true,
            };
            const rollbackEntry = this.otaTaskDeviceRepo.create({
                task_id: taskId,
                device_sn: td.device_sn,
                old_version: td.new_version,
                new_version: td.old_version,
                status: ota_task_device_entity_1.OtaTaskDeviceStatus.PENDING,
                progress: 0,
                mqtt_message: JSON.stringify(rollbackPayload),
            });
            await this.otaTaskDeviceRepo.save(rollbackEntry);
            try {
                await sendMqttCommand(td.device_sn, 'ota_rollback', rollbackPayload);
            }
            catch (err) {
                console.error(`[OTA] Rollback MQTT push failed for ${td.device_sn}:`, err.message);
            }
        }
        task.status = ota_task_entity_1.OtaTaskStatus.ROLLED_BACK;
        await this.otaTaskRepo.save(task);
        return task;
    }
    async retryDevice(taskId, deviceSn) {
        const taskDevice = await this.otaTaskDeviceRepo.findOne({
            where: { task_id: taskId, device_sn: deviceSn },
        });
        if (!taskDevice) {
            throw new common_1.NotFoundException('Task device entry not found');
        }
        if (taskDevice.status !== ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED) {
            throw new common_1.BadRequestException('Only failed devices can be retried');
        }
        const firmware = await this.firmwareRepo.findOne({
            where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } })).firmware_id },
        });
        taskDevice.status = ota_task_device_entity_1.OtaTaskDeviceStatus.PENDING;
        taskDevice.progress = 0;
        taskDevice.error_message = null;
        taskDevice.started_at = null;
        taskDevice.completed_at = null;
        await this.otaTaskDeviceRepo.save(taskDevice);
        const downloadUrl = firmware
            ? `http://${process.env.SERVER_HOST || 'localhost'}:${process.env.PORT || 3000}/static/${firmware.file_url}`
            : '';
        const mqttPayload = {
            task_id: taskId,
            firmware_url: downloadUrl,
            version: taskDevice.new_version,
            md5: firmware?.file_md5,
            sha256: firmware?.file_sha256,
            file_size: firmware?.file_size,
        };
        try {
            taskDevice.mqtt_message = JSON.stringify(mqttPayload);
            taskDevice.status = ota_task_device_entity_1.OtaTaskDeviceStatus.DOWNLOADING;
            taskDevice.started_at = new Date();
            await this.otaTaskDeviceRepo.save(taskDevice);
            await sendMqttCommand(deviceSn, 'ota_upgrade', mqttPayload);
        }
        catch (err) {
            taskDevice.status = ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED;
            taskDevice.error_message = err.message || 'MQTT retry push failed';
            taskDevice.completed_at = new Date();
            await this.otaTaskDeviceRepo.save(taskDevice);
        }
        return taskDevice;
    }
    async updateDeviceProgress(taskId, deviceSn, statusStr, progress) {
        const taskDevice = await this.otaTaskDeviceRepo.findOne({
            where: { task_id: taskId, device_sn: deviceSn },
        });
        if (!taskDevice) {
            throw new common_1.NotFoundException('Task device entry not found');
        }
        const validStatuses = Object.values(ota_task_device_entity_1.OtaTaskDeviceStatus);
        const newStatus = statusStr;
        if (!validStatuses.includes(newStatus)) {
            throw new common_1.BadRequestException(`Invalid status: ${statusStr}`);
        }
        taskDevice.status = newStatus;
        taskDevice.progress = progress;
        if (newStatus === ota_task_device_entity_1.OtaTaskDeviceStatus.DOWNLOADING && !taskDevice.started_at) {
            taskDevice.started_at = new Date();
        }
        if (newStatus === ota_task_device_entity_1.OtaTaskDeviceStatus.SUCCESS ||
            newStatus === ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED) {
            taskDevice.completed_at = new Date();
        }
        await this.otaTaskDeviceRepo.save(taskDevice);
        await this.updateTaskCounts(taskId);
        return taskDevice;
    }
    async updateTaskCounts(taskId) {
        const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
        if (!task)
            return;
        const stats = await this.otaTaskDeviceRepo
            .createQueryBuilder('td')
            .select('td.status', 'status')
            .addSelect('COUNT(*)', 'count')
            .where('td.task_id = :taskId', { taskId })
            .groupBy('td.status')
            .getRawMany();
        let successCount = 0;
        let failedCount = 0;
        for (const row of stats) {
            if (row.status === ota_task_device_entity_1.OtaTaskDeviceStatus.SUCCESS) {
                successCount = Number(row.count);
            }
            else if (row.status === ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED) {
                failedCount = Number(row.count);
            }
        }
        task.success_count = successCount;
        task.failed_count = failedCount;
        if (successCount + failedCount >= task.total_devices) {
            task.status = failedCount > 0 ? ota_task_entity_1.OtaTaskStatus.FAILED : ota_task_entity_1.OtaTaskStatus.COMPLETED;
        }
        else if (successCount > 0 &&
            task.status === ota_task_entity_1.OtaTaskStatus.PUSHING) {
            task.status = ota_task_entity_1.OtaTaskStatus.IN_PROGRESS;
        }
        await this.otaTaskRepo.save(task);
    }
    async cancelTask(taskId) {
        const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
        if (!task) {
            throw new common_1.NotFoundException('OTA Task not found');
        }
        if (task.status === ota_task_entity_1.OtaTaskStatus.COMPLETED ||
            task.status === ota_task_entity_1.OtaTaskStatus.CANCELLED) {
            throw new common_1.BadRequestException('Task cannot be cancelled in current status');
        }
        await this.otaTaskDeviceRepo.update({
            task_id: taskId,
            status: ota_task_device_entity_1.OtaTaskDeviceStatus.PENDING,
        }, {
            status: ota_task_device_entity_1.OtaTaskDeviceStatus.FAILED,
            error_message: 'Task cancelled',
            completed_at: new Date(),
        });
        task.status = ota_task_entity_1.OtaTaskStatus.CANCELLED;
        return this.otaTaskRepo.save(task);
    }
};
exports.OtaService = OtaService;
exports.OtaService = OtaService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(firmware_entity_1.Firmware)),
    __param(1, (0, typeorm_1.InjectRepository)(ota_task_entity_1.OtaTask)),
    __param(2, (0, typeorm_1.InjectRepository)(ota_task_device_entity_1.OtaTaskDevice)),
    __param(3, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository])
], OtaService);
//# sourceMappingURL=ota.service.js.map