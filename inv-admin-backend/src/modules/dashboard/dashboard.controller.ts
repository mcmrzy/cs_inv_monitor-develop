import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { DashboardService } from './dashboard.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('dashboard')
@UseGuards(JwtAuthGuard)
export class DashboardController {
  constructor(private readonly dashboardService: DashboardService) {}

  @Get('statistics')
  async getStatistics(
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.dashboardService.getStatistics(user);
  }

  @Get('trend')
  async getTrend(
    @Query('type') type: string = 'day',
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.dashboardService.getTrend(type as 'day' | 'month' | 'year', user);
  }

  @Get('device-distribution')
  async getDeviceDistribution(
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.dashboardService.getDeviceStatusDistribution(user);
  }

  @Get('big-screen')
  async getBigScreen(
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.dashboardService.getBigScreen(user);
  }

  @Get('compare')
  async compareDevices(
    @Query('devices') devices: string,
    @Query('metric') metric: string,
    @CurrentUser() user: { id: number; role: Role },
    @Query('startTime') startTime?: string,
    @Query('endTime') endTime?: string,
  ) {
    return this.dashboardService.compareDevices(devices, metric, startTime ?? '', endTime ?? '', user);
  }
}
