import { Controller, Get, Post, Patch, Delete, Body, Param, Query, ParseIntPipe, UseGuards } from '@nestjs/common';
import { ParallelService } from './parallel.service';
import { CreateParallelGroupDto, UpdateParallelGroupDto, QueryParallelGroupDto, SyncParamsDto } from './dto/create-parallel-group.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('parallel-groups')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class ParallelController {
  constructor(private readonly parallelService: ParallelService) {}

  @Get()
  @RequirePermission('parallel', 'view')
  findAll(@Query() query: QueryParallelGroupDto) { return this.parallelService.getAllGroups(query); }

  @Get(':id')
  @RequirePermission('parallel', 'view')
  getDetail(@Param('id', ParseIntPipe) id: number) { return this.parallelService.getGroupDetail(id); }

  @Post()
  @RequirePermission('parallel', 'create')
  create(@Body() dto: CreateParallelGroupDto, @CurrentUser() user: any) {
    return this.parallelService.createGroup(dto, user.id ?? user.sub);
  }

  @Patch(':id')
  @RequirePermission('parallel', 'create')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateParallelGroupDto) {
    return this.parallelService.updateGroup(id, dto);
  }

  @Delete(':id')
  @RequirePermission('parallel', 'create')
  delete(@Param('id', ParseIntPipe) id: number) { return this.parallelService.deleteGroup(id); }

  @Post(':id/sync')
  @RequirePermission('parallel', 'control')
  syncParams(@Param('id', ParseIntPipe) id: number, @Body() params: SyncParamsDto) {
    return this.parallelService.syncParams(id, params);
  }

  @Get(':id/status')
  @RequirePermission('parallel', 'view')
  getStatus(@Param('id', ParseIntPipe) id: number) { return this.parallelService.getGroupStatus(id); }

  @Get(':id/alerts')
  @RequirePermission('parallel', 'view')
  getAlerts(@Param('id', ParseIntPipe) id: number, @Query('page') page?: number, @Query('pageSize') pageSize?: number) {
    return this.parallelService.getAlertHistory(id, { page, pageSize });
  }
}
