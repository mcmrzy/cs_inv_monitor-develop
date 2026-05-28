import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ParallelConfig } from '../../entities/parallel-config.entity';
import { ParallelStatus } from '../../entities/parallel-status.entity';
import { Device } from '../../entities/device.entity';
import { Alert } from '../../entities/alert.entity';
import { ParallelService } from './parallel.service';
import { ParallelController } from './parallel.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([ParallelConfig, ParallelStatus, Device, Alert]),
  ],
  controllers: [ParallelController],
  providers: [ParallelService],
  exports: [ParallelService],
})
export class ParallelModule {}
