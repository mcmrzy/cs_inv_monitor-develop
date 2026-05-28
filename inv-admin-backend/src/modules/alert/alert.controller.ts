import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  ParseIntPipe,
  UseGuards,
} from '@nestjs/common';
import { AlertService } from './alert.service';
import { QueryAlertDto } from './dto/query-alert.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Role } from '../../common/enums/role.enum';

@Controller('alerts')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class AlertController {
  constructor(private readonly alertService: AlertService) {}

  @Get()
  @RequirePermission('alerts', 'view')
  async findAll(
    @Query() query: QueryAlertDto,
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.alertService.findAll(query, user);
  }

  @Post(':id/acknowledge')
  @RequirePermission('alerts', 'manage')
  async acknowledge(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.alertService.acknowledge(id, user.id);
  }

  @Post(':id/ignore')
  @RequirePermission('alerts', 'manage')
  async ignore(
    @Param('id', ParseIntPipe) id: number,
    @CurrentUser() user: { id: number; role: Role },
  ) {
    return this.alertService.ignore(id, user.id);
  }
}
