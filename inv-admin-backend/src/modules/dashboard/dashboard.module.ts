import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';
import { User } from '../../entities/user.entity';
import { Alert } from '../../entities/alert.entity';
import { DeviceTelemetry } from '../../entities/device-telemetry.entity';
import { Firmware } from '../../entities/firmware.entity';
import { OtaTask } from '../../entities/ota-task.entity';
import { DashboardService } from './dashboard.service';
import { DashboardController } from './dashboard.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Device, Station, User, Alert, DeviceTelemetry, Firmware, OtaTask])],
  controllers: [DashboardController],
  providers: [DashboardService],
})
export class DashboardModule {}
