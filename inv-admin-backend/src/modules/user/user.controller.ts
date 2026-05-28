import { Controller, Get, Post, Patch, Delete, Put, Body, Param, Query, UseGuards, ParseIntPipe } from '@nestjs/common';
import { UserService } from './user.service';
import { CreateUserDto, UpdateUserDto, QueryUserDto, ResetPasswordDto } from './dto/create-user.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PermissionGuard } from '../../common/guards/permission.guard';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';

@Controller('users')
@UseGuards(JwtAuthGuard, PermissionGuard)
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Get()
  @RequirePermission('users', 'view')
  findAll(@Query() query: QueryUserDto, @CurrentUser() currentUser: any) {
    return this.userService.findAll(query, currentUser);
  }

  @Post()
  @RequirePermission('users', 'create')
  create(@Body() dto: CreateUserDto, @CurrentUser() currentUser: any) {
    return this.userService.create(dto, currentUser);
  }

  @Get(':id')
  @RequirePermission('users', 'view')
  findById(@Param('id', ParseIntPipe) id: number, @CurrentUser() currentUser: any) {
    return this.userService.findById(id, currentUser);
  }

  @Patch(':id')
  @RequirePermission('users', 'edit')
  update(@Param('id', ParseIntPipe) id: number, @Body() dto: UpdateUserDto, @CurrentUser() currentUser: any) {
    return this.userService.update(id, dto, currentUser);
  }

  @Delete(':id')
  @RequirePermission('users', 'delete')
  disable(@Param('id', ParseIntPipe) id: number) {
    return this.userService.disable(id);
  }

  @Put(':id/password')
  @RequirePermission('users', 'manage')
  resetPassword(@Param('id', ParseIntPipe) id: number, @Body() dto: ResetPasswordDto) {
    return this.userService.resetPassword(id, dto.newPassword);
  }
}
