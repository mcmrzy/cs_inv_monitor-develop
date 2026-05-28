import {
  Controller, Get, Post, Patch, Param, Query, Body, UseGuards, UseInterceptors, UploadedFiles, ParseUUIDPipe,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { extname } from 'path';
import { AlertService } from './alert.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Role } from '../../common/enums/role.enum';
import { CreateWorkOrderDto } from './dto/create-work-order.dto';
import { WorkOrder, WorkOrderStatus } from '../../entities/work-order.entity';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { v4 as uuidv4 } from 'uuid';

@Controller('work-orders')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class WorkOrderController {
  constructor(
    private readonly alertService: AlertService,
    @InjectRepository(WorkOrder)
    private workOrderRepo: Repository<WorkOrder>,
  ) {}

  @Get('templates')
  @RequirePermission('work_orders', 'view')
  async getTemplates() {
    return this.alertService.getTemplates();
  }

  @Get()
  @RequirePermission('work_orders', 'view')
  async getWorkOrders(@Query() query: any, @CurrentUser() user: { id: number; role: Role }) {
    return this.alertService.getWorkOrders(query, user);
  }

  @Post()
  @RequirePermission('work_orders', 'create')
  async createWorkOrder(@Body() dto: CreateWorkOrderDto, @CurrentUser() user: { id: number; role: Role }) {
    return this.alertService.createWorkOrder(dto, user.id);
  }

  @Get(':id')
  @RequirePermission('work_orders', 'view')
  async getWorkOrder(@Param('id', ParseUUIDPipe) id: string) {
    return this.alertService.getWorkOrder(id);
  }

  @Patch(':id')
  @RequirePermission('work_orders', 'edit')
  async updateWorkOrder(@Param('id', ParseUUIDPipe) id: string, @Body() body: { assignedTo?: number }) {
    if (body.assignedTo) return this.alertService.assignWorkOrder(id, body.assignedTo);
    return { message: '无效的更新操作' };
  }

  @Patch(':id/status')
  @RequirePermission('work_orders', 'edit')
  async updateWorkOrderStatus(@Param('id', ParseUUIDPipe) id: string, @Body() body: { status: WorkOrderStatus; resolution?: string }) {
    return this.alertService.updateWorkOrderStatus(id, body.status, body.resolution);
  }

  @Post(':id/escalate')
  @RequirePermission('work_orders', 'manage')
  async escalateWorkOrder(@Param('id', ParseUUIDPipe) id: string) {
    return this.alertService.escalateWorkOrder(id);
  }

  @Post(':id/attachments')
  @RequirePermission('work_orders', 'edit')
  @UseInterceptors(FilesInterceptor('files', 5, {
    storage: diskStorage({
      destination: './uploads/work-orders',
      filename: (_req, file, cb) => { const uniqueSuffix = uuidv4(); cb(null, `${uniqueSuffix}${extname(file.originalname)}`); },
    }),
    fileFilter: (_req, file, cb) => {
      if (!file.mimetype.match(/^image\//)) { cb(new Error('只允许上传图片文件'), false); return; }
      cb(null, true);
    },
  }))
  async uploadAttachments(@Param('id', ParseUUIDPipe) id: string, @UploadedFiles() files: Express.Multer.File[]) {
    const workOrder = await this.workOrderRepo.findOne({ where: { id } });
    if (!workOrder) return { message: '工单不存在' };
    const existingAttachments = workOrder.attachments || [];
    if (existingAttachments.length + files.length > 10) return { message: '每个工单最多上传10张图片' };
    const newAttachments = files.map((file) => ({ name: file.originalname, url: `/uploads/work-orders/${file.filename}`, type: file.mimetype, uploadedAt: new Date().toISOString() }));
    workOrder.attachments = [...existingAttachments, ...newAttachments];
    await this.workOrderRepo.save(workOrder);
    return { message: '上传成功', attachments: workOrder.attachments };
  }
}
