import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Body,
  Param,
  Query,
  Req,
  Res,
  UseGuards,
  UseInterceptors,
  UploadedFile,
} from '@nestjs/common';
import { Response } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { DeviceService } from './device.service';
import { ExcelImportService } from './excel-import.service';
import { CreateDeviceDto, UpdateDeviceDto, QueryDeviceDto } from './dto/create-device.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('devices')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class DeviceController {
  constructor(
    private readonly deviceService: DeviceService,
    private readonly excelImportService: ExcelImportService,
  ) {}

  @Get()
  @RequirePermission('devices', 'view')
  findAll(@Query() query: QueryDeviceDto, @CurrentUser() currentUser: any) {
    return this.deviceService.findAll(query, currentUser);
  }

  @Get('unbind-requests')
  @RequirePermission('devices', 'manage')
  getUnbindRequests(
    @Query('status') status?: string,
    @Query('page') page?: number,
    @Query('pageSize') pageSize?: number,
  ) {
    return this.deviceService.getUnbindRequests({ status, page, pageSize });
  }

  @Get(':sn')
  @RequirePermission('devices', 'view')
  findBySn(@Param('sn') sn: string, @CurrentUser() currentUser: any) {
    return this.deviceService.findBySn(sn, currentUser);
  }

  @Get(':sn/lifecycle')
  @RequirePermission('devices', 'manage')
  getLifecycleHistory(
    @Param('sn') sn: string,
    @Query('page') page?: number,
    @Query('pageSize') pageSize?: number,
  ) {
    return this.deviceService.getLifecycleHistory(sn, page, pageSize);
  }

  @Post()
  @RequirePermission('devices', 'create')
  create(@Body() dto: CreateDeviceDto, @CurrentUser() currentUser: any) {
    return this.deviceService.create(dto, currentUser);
  }

  @Post('import-excel')
  @RequirePermission('devices', 'create')
  @UseInterceptors(FileInterceptor('file'))
  async importExcel(
    @UploadedFile() file: Express.Multer.File,
    @CurrentUser() currentUser: any,
    @Body('installerId') installerId?: number,
  ) {
    const rows = this.excelImportService.parseExcel(file.buffer);
    const userId = currentUser.id ?? currentUser.sub;
    const installer = installerId ?? userId;
    return this.excelImportService.bulkImport(rows, userId, installer);
  }

  @Post(':sn/request-unbind')
  @RequirePermission('devices', 'manage')
  requestUnbind(
    @Param('sn') sn: string,
    @Body() body: { reason: string },
    @CurrentUser() currentUser: any,
  ) {
    const userId = currentUser.id ?? currentUser.sub;
    return this.deviceService.requestUnbind(sn, userId, body.reason);
  }

  @Post('unbind-requests/:id/approve')
  @RequirePermission('devices', 'manage')
  approveUnbind(
    @Param('id') id: number,
    @Body() body: { comment?: string },
    @CurrentUser() currentUser: any,
  ) {
    const userId = currentUser.id ?? currentUser.sub;
    return this.deviceService.approveUnbind(id, userId, body.comment ?? '');
  }

  @Post('unbind-requests/:id/reject')
  @RequirePermission('devices', 'manage')
  rejectUnbind(
    @Param('id') id: number,
    @Body() body: { comment?: string },
    @CurrentUser() currentUser: any,
  ) {
    const userId = currentUser.id ?? currentUser.sub;
    return this.deviceService.rejectUnbind(id, userId, body.comment ?? '');
  }

  @Put(':sn')
  @RequirePermission('devices', 'edit')
  update(
    @Param('sn') sn: string,
    @Body() dto: UpdateDeviceDto,
    @CurrentUser() currentUser: any,
  ) {
    return this.deviceService.update(sn, dto, currentUser);
  }

  @Delete(':sn')
  @RequirePermission('devices', 'delete')
  delete(@Param('sn') sn: string) {
    return this.deviceService.delete(sn);
  }

  @Post(':sn/unbind')
  @RequirePermission('devices', 'manage')
  unbind(@Param('sn') sn: string, @CurrentUser() currentUser: any) {
    return this.deviceService.unbind(sn, currentUser);
  }

  @Get(':sn/telemetry')
  @RequirePermission('devices', 'view')
  getTelemetry(
    @Param('sn') sn: string,
    @Query('startTime') startTime?: string,
    @Query('endTime') endTime?: string,
    @Query('limit') limit?: number,
    @CurrentUser() currentUser?: any,
  ) {
    return this.deviceService.getTelemetry(sn, { startTime, endTime, limit }, currentUser);
  }

  @Get(':sn/realtime')
  @RequirePermission('devices', 'view')
  getRealtimeData(@Param('sn') sn: string, @CurrentUser() currentUser: any) {
    return this.deviceService.getRealtimeData(sn, currentUser);
  }

  @Get(':sn/commands')
  @RequirePermission('devices', 'view')
  getCommandTemplates(@Param('sn') sn: string) {
    return this.deviceService.getCommandTemplates(sn);
  }

  @Post(':sn/config')
  @RequirePermission('devices', 'control')
  sendConfig(
    @Param('sn') sn: string,
    @Body() body: { command: string; params: any },
    @CurrentUser() currentUser: any,
    @Req() req: any,
  ) {
    const userId = currentUser.id ?? currentUser.sub;
    const ipAddress = req.ip || req.connection?.remoteAddress;
    return this.deviceService.executeCommand(sn, body.command, body.params, userId, ipAddress);
  }

  @Get(':sn/commands/history')
  @RequirePermission('devices', 'view')
  getCommandHistory(
    @Param('sn') sn: string,
    @Query('page') page?: number,
    @Query('pageSize') pageSize?: number,
  ) {
    return this.deviceService.getCommandHistory(sn, page, pageSize);
  }

  @Get(':sn/telemetry/export')
  @RequirePermission('devices', 'export')
  async exportTelemetryCSV(
    @Param('sn') sn: string,
    @Query('startTime') startTime?: string,
    @Query('endTime') endTime?: string,
    @Query('fields') fields?: string,
    @CurrentUser() currentUser?: any,
    @Res() res?: Response,
  ) {
    const csv = await this.deviceService.exportTelemetryCSV(
      sn, startTime ?? '', endTime ?? '', fields ?? '', currentUser,
    );
    res!.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res!.setHeader('Content-Disposition', `attachment; filename="${sn}_telemetry_${Date.now()}.csv"`);
    res!.send(csv);
  }

  @Get(':sn/telemetry/export-excel')
  @RequirePermission('devices', 'export')
  async exportTelemetryExcel(
    @Param('sn') sn: string,
    @Query('startTime') startTime?: string,
    @Query('endTime') endTime?: string,
    @CurrentUser() currentUser?: any,
    @Res() res?: Response,
  ) {
    const buffer = await this.deviceService.exportTelemetryExcel(
      sn, startTime ?? '', endTime ?? '', currentUser,
    );
    res!.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res!.setHeader('Content-Disposition', `attachment; filename="${sn}_telemetry_${Date.now()}.xlsx"`);
    res!.send(buffer);
  }
}
