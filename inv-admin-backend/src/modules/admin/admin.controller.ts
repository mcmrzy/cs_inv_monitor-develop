import { Controller, Get, Post, Put, Patch, Query, Body, Param, UseGuards } from '@nestjs/common';
import { AdminService } from './admin.service';
import { PermissionService } from './permission.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';

@Controller('admin')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly permissionService: PermissionService,
  ) {}

  @Get('logs')
  @RequirePermission('audit', 'view')
  async getAuditLogs(@Query() query: any) { return this.adminService.getAuditLogs(query); }

  @Get('system-health')
  @RequirePermission('admin', 'view')
  async getSystemHealth() { return this.adminService.getSystemHealth(); }

  @Post('tenants')
  @RequirePermission('admin', 'manage')
  async createTenant(@Body() body: any) { return this.adminService.createTenant(body); }

  @Get('tenants')
  @RequirePermission('admin', 'manage')
  async getTenants(@Query('page') page?: number, @Query('pageSize') pageSize?: number) {
    return this.adminService.getTenants(page, pageSize);
  }

  @Patch('tenants/:id')
  @RequirePermission('admin', 'manage')
  async updateTenant(@Param('id') id: number, @Body() body: any) { return this.adminService.updateTenant(id, body); }

  @Post('tenants/:id/toggle')
  @RequirePermission('admin', 'manage')
  async toggleTenant(@Param('id') id: number) { return this.adminService.toggleTenant(id); }

  @Get('system-config')
  @RequirePermission('admin', 'view')
  async getSystemConfig() { return this.adminService.getSystemConfig(); }

  @Patch('system-config')
  @RequirePermission('admin', 'manage')
  async updateSystemConfig(@Body() body: any) { return this.adminService.updateSystemConfig(body); }

  @Get('permissions')
  @RequirePermission('admin', 'manage')
  async getAllPermissions() { return this.permissionService.getAllPermissionsConfig(); }

  @Get('permissions/:role')
  @RequirePermission('admin', 'manage')
  async getRolePermissions(@Param('role') role: number) { return this.permissionService.getRolePermissions(role); }

  @Put('permissions/:role')
  @RequirePermission('admin', 'manage')
  async updateRolePermissions(@Param('role') role: number, @Body() body: { permissions: { resource: string; action: string; is_allowed: boolean }[] }) {
    await this.permissionService.batchUpdatePermissions(role, body.permissions);
    return { success: true };
  }

  @Post('permissions/:role/toggle')
  @RequirePermission('admin', 'manage')
  async togglePermission(@Param('role') role: number, @Body() body: { resource: string; action: string; is_allowed: boolean }) {
    return this.permissionService.setPermission(role, body.resource, body.action, body.is_allowed);
  }
}
