import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Firmware } from '../../entities/firmware.entity';
import { OtaTask } from '../../entities/ota-task.entity';
import { OtaTaskDevice } from '../../entities/ota-task-device.entity';
import { Device } from '../../entities/device.entity';
import { OtaService } from './ota.service';
import { OtaController } from './ota.controller';

@Module({
  imports: [TypeOrmModule.forFeature([Firmware, OtaTask, OtaTaskDevice, Device])],
  providers: [OtaService],
  controllers: [OtaController],
})
export class OtaModule {}
