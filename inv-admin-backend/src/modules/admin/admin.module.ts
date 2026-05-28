import { Module, Global, OnModuleInit } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuditLog } from '../../entities/audit-log.entity';
import { User } from '../../entities/user.entity';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';
import { SystemConfig } from '../../entities/system-config.entity';
import { RolePermission } from '../../entities/permission.entity';
import { AdminService } from './admin.service';
import { PermissionService } from './permission.service';
import { GeoLocationService } from './geo-location.service';
import { AdminController } from './admin.controller';
import { MetricsController } from './metrics.controller';
import { HealthController } from './health.controller';
import { PrometheusMetrics } from '../../common/metrics/prometheus.metrics';

@Global()
@Module({
  imports: [TypeOrmModule.forFeature([AuditLog, User, Device, Station, SystemConfig, RolePermission])],
  controllers: [AdminController, MetricsController, HealthController],
  providers: [AdminService, PermissionService, GeoLocationService, PrometheusMetrics],
  exports: [PrometheusMetrics, PermissionService],
})
export class AdminModule implements OnModuleInit {
  constructor(private permissionService: PermissionService) {}

  async onModuleInit() {
    await this.permissionService.seedDefaults();
  }
}
