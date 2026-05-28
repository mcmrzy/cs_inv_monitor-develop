import { Controller, Get, Put, Body, Param, ParseIntPipe, UseGuards } from '@nestjs/common';
import { StationService } from './station.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('stations')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class StationController {
  constructor(private readonly stationService: StationService) {}

  @Get()
  @RequirePermission('stations', 'view')
  async findAll(@CurrentUser() user: { id: number; role: Role }) {
    return this.stationService.findAll(user);
  }

  @Put(':id/assign')
  @RequirePermission('stations', 'edit')
  async assignUser(
    @Param('id', ParseIntPipe) id: number,
    @Body() body: { user_id: number },
  ) {
    return this.stationService.assignUser(id, body.user_id);
  }

  @Put(':id')
  @RequirePermission('stations', 'edit')
  async update(
    @Param('id', ParseIntPipe) id: number,
    @Body() body: any,
  ) {
    return this.stationService.update(id, body);
  }
}
