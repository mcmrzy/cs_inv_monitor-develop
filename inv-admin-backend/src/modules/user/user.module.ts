import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from '../../entities/user.entity';
import { UserService } from './user.service';
import { UserController } from './user.controller';
import { ReAuthGuard } from '../../common/guards/re-auth.guard';

@Module({
  imports: [TypeOrmModule.forFeature([User])],
  providers: [UserService, ReAuthGuard],
  controllers: [UserController],
  exports: [UserService],
})
export class UserModule {}
