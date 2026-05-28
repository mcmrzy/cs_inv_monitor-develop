import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import { v4 as uuidv4 } from 'uuid';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import * as http from 'http';
import { Firmware } from '../../entities/firmware.entity';
import { OtaTask, OtaTaskStatus } from '../../entities/ota-task.entity';
import { OtaTaskDevice, OtaTaskDeviceStatus } from '../../entities/ota-task-device.entity';
import { Device } from '../../entities/device.entity';
import { CreateFirmwareDto } from './dto/create-firmware.dto';
import { CreateOtaTaskDto } from './dto/create-ota-task.dto';
import { QueryOtaTaskDto } from './dto/query-ota-task.dto';

const UPLOAD_DIR = path.resolve(process.cwd(), 'uploads', 'firmware');

function sendMqttCommand(deviceSn: string, command: string, payload: any): Promise<string> {
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

@Injectable()
export class OtaService {
  constructor(
    @InjectRepository(Firmware)
    private readonly firmwareRepo: Repository<Firmware>,
    @InjectRepository(OtaTask)
    private readonly otaTaskRepo: Repository<OtaTask>,
    @InjectRepository(OtaTaskDevice)
    private readonly otaTaskDeviceRepo: Repository<OtaTaskDevice>,
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
  ) {}

  async uploadFirmware(file: Express.Multer.File, dto: CreateFirmwareDto, userId: number): Promise<Firmware> {
    const modelDir = path.join(UPLOAD_DIR, dto.model, dto.version);
    if (!fs.existsSync(modelDir)) {
      fs.mkdirSync(modelDir, { recursive: true });
    }

    const destPath = path.join(modelDir, file.originalname);

    if (file.buffer) {
      fs.writeFileSync(destPath, file.buffer);
    } else if (file.path) {
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

  async getFirmwares(query: { model?: string; page?: number; pageSize?: number }): Promise<{
    items: Firmware[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const skip = (page - 1) * pageSize;

    const where: any = {};
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

  async deleteFirmware(id: number): Promise<void> {
    const firmware = await this.firmwareRepo.findOne({ where: { id } });
    if (!firmware) {
      throw new NotFoundException('Firmware not found');
    }
    await this.firmwareRepo.remove(firmware);
  }

  async createTask(dto: CreateOtaTaskDto, userId: number): Promise<OtaTask> {
    const firmware = await this.firmwareRepo.findOne({ where: { id: dto.firmwareId } });
    if (!firmware) {
      throw new NotFoundException('Firmware not found');
    }

    const devices = await this.deviceRepo.find({
      where: { sn: In(dto.deviceSns) },
    });

    if (devices.length !== dto.deviceSns.length) {
      const foundSns = devices.map((d) => d.sn);
      const missing = dto.deviceSns.filter((sn) => !foundSns.includes(sn));
      throw new BadRequestException(`Devices not found: ${missing.join(', ')}`);
    }

    const taskId = uuidv4();
    const task = this.otaTaskRepo.create({
      id: taskId,
      name: dto.name,
      firmware_id: firmware.id,
      created_by: userId,
      status: OtaTaskStatus.PENDING,
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
        status: OtaTaskDeviceStatus.PENDING,
        progress: 0,
      });
    });

    await this.otaTaskDeviceRepo.save(taskDevices);

    return task;
  }

  async getTasks(query: QueryOtaTaskDto, currentUser: any): Promise<{
    items: OtaTask[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const skip = (page - 1) * pageSize;

    const where: any = {};
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

  async getTaskDetail(taskId: string): Promise<OtaTask> {
    const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
    if (!task) {
      throw new NotFoundException('OTA Task not found');
    }
    return task;
  }

  async getTaskDevices(taskId: string, query: { page?: number; pageSize?: number }): Promise<{
    items: OtaTaskDevice[];
    total: number;
    page: number;
    pageSize: number;
  }> {
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

  async executeTask(taskId: string): Promise<OtaTask> {
    const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
    if (!task) {
      throw new NotFoundException('OTA Task not found');
    }

    if (task.status !== OtaTaskStatus.PENDING) {
      throw new BadRequestException('Task can only be executed from pending status');
    }

    task.status = OtaTaskStatus.PUSHING;
    await this.otaTaskRepo.save(task);

    this.runExecutionStrategy(task).catch((err) => {
      console.error(`[OTA] Task ${taskId} execution error:`, err);
    });

    return task;
  }

  private async runExecutionStrategy(task: OtaTask): Promise<void> {
    const taskId = task.id;
    const strategy = task.push_strategy || 'all_at_once';
    const percentage = task.push_percentage || 100;
    const batchSize = task.batch_size || 10;

    const allPendingDevices = await this.otaTaskDeviceRepo.find({
      where: { task_id: taskId, status: OtaTaskDeviceStatus.PENDING },
    });

    if (allPendingDevices.length === 0) return;

    let devicesToPush: OtaTaskDevice[];

    if (strategy === 'percentage') {
      const count = Math.max(1, Math.floor(allPendingDevices.length * percentage / 100));
      const shuffled = [...allPendingDevices].sort(() => Math.random() - 0.5);
      devicesToPush = shuffled.slice(0, count);
    } else {
      devicesToPush = allPendingDevices;
    }

    if (strategy === 'batch') {
      await this.pushInBatches(taskId, devicesToPush, batchSize);
    } else {
      await this.pushAllAtOnce(taskId, devicesToPush);
    }
  }

  private async pushAllAtOnce(taskId: string, devices: OtaTaskDevice[]): Promise<void> {
    const firmware = await this.firmwareRepo.findOne({
      where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } }))!.firmware_id },
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
        td.status = OtaTaskDeviceStatus.DOWNLOADING;
        td.started_at = new Date();
        await this.otaTaskDeviceRepo.save(td);

        await sendMqttCommand(td.device_sn, 'ota_upgrade', mqttPayload);
      } catch (err: any) {
        td.status = OtaTaskDeviceStatus.FAILED;
        td.error_message = err.message || 'MQTT push failed';
        td.completed_at = new Date();
        await this.otaTaskDeviceRepo.save(td);
      }
    }

    await this.updateTaskCounts(taskId);
  }

  private async pushInBatches(taskId: string, devices: OtaTaskDevice[], batchSize: number): Promise<void> {
    const firmware = await this.firmwareRepo.findOne({
      where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } }))!.firmware_id },
    });

    const downloadUrl = firmware
      ? `http://${process.env.SERVER_HOST || 'localhost'}:${process.env.PORT || 3000}/static/${firmware.file_url}`
      : '';

    for (let i = 0; i < devices.length; i += batchSize) {
      const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
      if (!task || task.status === OtaTaskStatus.CANCELLED) break;

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
          td.status = OtaTaskDeviceStatus.DOWNLOADING;
          td.started_at = new Date();
          await this.otaTaskDeviceRepo.save(td);

          await sendMqttCommand(td.device_sn, 'ota_upgrade', mqttPayload);
        } catch (err: any) {
          td.status = OtaTaskDeviceStatus.FAILED;
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

  async rollbackTask(taskId: string): Promise<OtaTask> {
    const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
    if (!task) {
      throw new NotFoundException('OTA Task not found');
    }

    if (task.status !== OtaTaskStatus.COMPLETED && task.status !== OtaTaskStatus.FAILED) {
      throw new BadRequestException('Only completed or failed tasks can be rolled back');
    }

    const successDevices = await this.otaTaskDeviceRepo.find({
      where: { task_id: taskId, status: OtaTaskDeviceStatus.SUCCESS },
    });

    if (successDevices.length === 0) {
      throw new BadRequestException('No successfully upgraded devices to roll back');
    }

    const firmware = await this.firmwareRepo.findOne({ where: { id: task.firmware_id } });

    for (const td of successDevices) {
      if (!td.old_version) continue;

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
        status: OtaTaskDeviceStatus.PENDING,
        progress: 0,
        mqtt_message: JSON.stringify(rollbackPayload),
      });

      await this.otaTaskDeviceRepo.save(rollbackEntry);

      try {
        await sendMqttCommand(td.device_sn, 'ota_rollback', rollbackPayload);
      } catch (err: any) {
        console.error(`[OTA] Rollback MQTT push failed for ${td.device_sn}:`, err.message);
      }
    }

    task.status = OtaTaskStatus.ROLLED_BACK;
    await this.otaTaskRepo.save(task);

    return task;
  }

  async retryDevice(taskId: string, deviceSn: string): Promise<OtaTaskDevice> {
    const taskDevice = await this.otaTaskDeviceRepo.findOne({
      where: { task_id: taskId, device_sn: deviceSn },
    });

    if (!taskDevice) {
      throw new NotFoundException('Task device entry not found');
    }

    if (taskDevice.status !== OtaTaskDeviceStatus.FAILED) {
      throw new BadRequestException('Only failed devices can be retried');
    }

    const firmware = await this.firmwareRepo.findOne({
      where: { id: (await this.otaTaskRepo.findOne({ where: { id: taskId } }))!.firmware_id },
    });

    taskDevice.status = OtaTaskDeviceStatus.PENDING;
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
      taskDevice.status = OtaTaskDeviceStatus.DOWNLOADING;
      taskDevice.started_at = new Date();
      await this.otaTaskDeviceRepo.save(taskDevice);
      await sendMqttCommand(deviceSn, 'ota_upgrade', mqttPayload);
    } catch (err: any) {
      taskDevice.status = OtaTaskDeviceStatus.FAILED;
      taskDevice.error_message = err.message || 'MQTT retry push failed';
      taskDevice.completed_at = new Date();
      await this.otaTaskDeviceRepo.save(taskDevice);
    }

    return taskDevice;
  }

  async updateDeviceProgress(
    taskId: string,
    deviceSn: string,
    statusStr: string,
    progress: number,
  ): Promise<OtaTaskDevice> {
    const taskDevice = await this.otaTaskDeviceRepo.findOne({
      where: { task_id: taskId, device_sn: deviceSn },
    });

    if (!taskDevice) {
      throw new NotFoundException('Task device entry not found');
    }

    const validStatuses = Object.values(OtaTaskDeviceStatus);
    const newStatus = statusStr as OtaTaskDeviceStatus;
    if (!validStatuses.includes(newStatus)) {
      throw new BadRequestException(`Invalid status: ${statusStr}`);
    }

    taskDevice.status = newStatus;
    taskDevice.progress = progress;

    if (newStatus === OtaTaskDeviceStatus.DOWNLOADING && !taskDevice.started_at) {
      taskDevice.started_at = new Date();
    }

    if (
      newStatus === OtaTaskDeviceStatus.SUCCESS ||
      newStatus === OtaTaskDeviceStatus.FAILED
    ) {
      taskDevice.completed_at = new Date();
    }

    await this.otaTaskDeviceRepo.save(taskDevice);

    await this.updateTaskCounts(taskId);

    return taskDevice;
  }

  private async updateTaskCounts(taskId: string): Promise<void> {
    const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
    if (!task) return;

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
      if (row.status === OtaTaskDeviceStatus.SUCCESS) {
        successCount = Number(row.count);
      } else if (row.status === OtaTaskDeviceStatus.FAILED) {
        failedCount = Number(row.count);
      }
    }

    task.success_count = successCount;
    task.failed_count = failedCount;

    if (successCount + failedCount >= task.total_devices) {
      task.status = failedCount > 0 ? OtaTaskStatus.FAILED : OtaTaskStatus.COMPLETED;
    } else if (
      successCount > 0 &&
      task.status === OtaTaskStatus.PUSHING
    ) {
      task.status = OtaTaskStatus.IN_PROGRESS;
    }

    await this.otaTaskRepo.save(task);
  }

  async cancelTask(taskId: string): Promise<OtaTask> {
    const task = await this.otaTaskRepo.findOne({ where: { id: taskId } });
    if (!task) {
      throw new NotFoundException('OTA Task not found');
    }

    if (
      task.status === OtaTaskStatus.COMPLETED ||
      task.status === OtaTaskStatus.CANCELLED
    ) {
      throw new BadRequestException('Task cannot be cancelled in current status');
    }

    await this.otaTaskDeviceRepo.update(
      {
        task_id: taskId,
        status: OtaTaskDeviceStatus.PENDING,
      },
      {
        status: OtaTaskDeviceStatus.FAILED,
        error_message: 'Task cancelled',
        completed_at: new Date(),
      },
    );

    task.status = OtaTaskStatus.CANCELLED;
    return this.otaTaskRepo.save(task);
  }
}
