import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Device } from '../../entities/device.entity';
import { DeviceTelemetry } from '../../entities/device-telemetry.entity';
import { DeviceUnbindRequest } from '../../entities/device-unbind-request.entity';
import { DeviceLifecycle } from '../../entities/device-lifecycle.entity';
import { CommandLog } from '../../entities/command-log.entity';
import { Station } from '../../entities/station.entity';
import { User } from '../../entities/user.entity';
import { DeviceService } from './device.service';
import { ExcelImportService } from './excel-import.service';
import { CommandExecutionService } from './command-execution.service';
import { DeviceServerProxyService } from './device-server-proxy.service';
import { DeviceController } from './device.controller';
import { ReAuthGuard } from '../../common/guards/re-auth.guard';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Device,
      DeviceTelemetry,
      DeviceUnbindRequest,
      DeviceLifecycle,
      CommandLog,
      Station,
      User,
    ]),
  ],
  providers: [DeviceService, ExcelImportService, CommandExecutionService, DeviceServerProxyService, ReAuthGuard],
  controllers: [DeviceController],
})
export class DeviceModule {}
