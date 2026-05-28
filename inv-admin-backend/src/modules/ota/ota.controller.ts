import { Controller, Get, Post, Delete, Body, Param, Query, UseGuards, UseInterceptors, UploadedFile, ParseIntPipe } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { OtaService } from './ota.service';
import { CreateFirmwareDto } from './dto/create-firmware.dto';
import { CreateOtaTaskDto } from './dto/create-ota-task.dto';
import { QueryOtaTaskDto } from './dto/query-ota-task.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller()
@UseGuards(JwtAuthGuard, PermissionGuard)
export class OtaController {
  constructor(private readonly otaService: OtaService) {}

  @Post('firmwares')
  @RequirePermission('firmware', 'create')
  @UseInterceptors(FileInterceptor('file'))
  uploadFirmware(@UploadedFile() file: Express.Multer.File, @Body() dto: CreateFirmwareDto, @CurrentUser() currentUser: any) {
    return this.otaService.uploadFirmware(file, dto, currentUser.id ?? currentUser.sub);
  }

  @Get('firmwares')
  @RequirePermission('firmware', 'view')
  getFirmwares(@Query('model') model?: string, @Query('page') page?: number, @Query('pageSize') pageSize?: number) {
    return this.otaService.getFirmwares({ model, page, pageSize });
  }

  @Delete('firmwares/:id')
  @RequirePermission('firmware', 'delete')
  deleteFirmware(@Param('id', ParseIntPipe) id: number) { return this.otaService.deleteFirmware(id); }

  @Post('ota/tasks')
  @RequirePermission('ota', 'create')
  createTask(@Body() dto: CreateOtaTaskDto, @CurrentUser() currentUser: any) {
    return this.otaService.createTask(dto, currentUser.id ?? currentUser.sub);
  }

  @Get('ota/tasks')
  @RequirePermission('ota', 'view')
  getTasks(@Query() query: QueryOtaTaskDto, @CurrentUser() currentUser: any) {
    return this.otaService.getTasks(query, currentUser);
  }

  @Get('ota/tasks/:id')
  @RequirePermission('ota', 'view')
  getTaskDetail(@Param('id') id: string) { return this.otaService.getTaskDetail(id); }

  @Get('ota/tasks/:id/devices')
  @RequirePermission('ota', 'view')
  getTaskDevices(@Param('id') id: string, @Query('page') page?: number, @Query('pageSize') pageSize?: number) {
    return this.otaService.getTaskDevices(id, { page, pageSize });
  }

  @Post('ota/tasks/:id/execute')
  @RequirePermission('ota', 'control')
  executeTask(@Param('id') id: string) { return this.otaService.executeTask(id); }

  @Post('ota/tasks/:id/cancel')
  @RequirePermission('ota', 'control')
  cancelTask(@Param('id') id: string) { return this.otaService.cancelTask(id); }

  @Post('ota/tasks/:id/retry/:deviceSn')
  @RequirePermission('ota', 'control')
  retryDevice(@Param('id') id: string, @Param('deviceSn') deviceSn: string) {
    return this.otaService.retryDevice(id, deviceSn);
  }

  @Post('ota/tasks/:id/rollback')
  @RequirePermission('ota', 'control')
  rollbackTask(@Param('id') id: string) { return this.otaService.rollbackTask(id); }
}
