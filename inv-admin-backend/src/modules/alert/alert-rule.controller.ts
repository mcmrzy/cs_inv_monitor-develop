import { Controller, Get, Post, Put, Delete, Param, Query, Body, ParseIntPipe, UseGuards } from '@nestjs/common';
import { AlertRuleService } from './alert-rule.service';
import { CreateAlertRuleDto } from './dto/create-alert-rule.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('alert-rules')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class AlertRuleController {
  constructor(private readonly alertRuleService: AlertRuleService) {}

  @Get()
  @RequirePermission('alert_rules', 'view')
  async findAll(
    @Query('page') page?: number,
    @Query('pageSize') pageSize?: number,
    @Query('isActive') isActive?: string,
    @Query('deviceModel') deviceModel?: string,
  ) {
    return this.alertRuleService.findAll({ page, pageSize, isActive: isActive === undefined ? undefined : isActive === 'true', deviceModel });
  }

  @Post()
  @RequirePermission('alert_rules', 'create')
  async create(@Body() dto: CreateAlertRuleDto, @CurrentUser() user: { id: number; role: Role }) {
    return this.alertRuleService.create(dto, user);
  }

  @Put(':id')
  @RequirePermission('alert_rules', 'edit')
  async update(@Param('id', ParseIntPipe) id: number, @Body() dto: CreateAlertRuleDto) {
    return this.alertRuleService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermission('alert_rules', 'delete')
  async delete(@Param('id', ParseIntPipe) id: number) {
    await this.alertRuleService.delete(id);
    return { message: '规则已停用' };
  }
}
