import { IsString, IsOptional, IsNumber, IsInt, IsIn } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateDeviceDto {
  @IsString()
  sn: string;

  @IsOptional()
  @IsString()
  model?: string;

  @IsOptional()
  @IsNumber()
  ratedPower?: number;

  @IsOptional()
  @IsString()
  firmwareVersion?: string;

  @IsOptional()
  @IsNumber()
  stationId?: number;

  @IsOptional()
  @IsNumber()
  userId?: number;

  @IsOptional()
  @IsNumber()
  installerId?: number;
}

export class UpdateDeviceDto {
  @IsOptional()
  @IsString()
  model?: string;

  @IsOptional()
  @IsNumber()
  ratedPower?: number;

  @IsOptional()
  @IsString()
  firmwareVersion?: string;

  @IsOptional()
  @IsNumber()
  stationId?: number;

  @IsOptional()
  @IsNumber()
  userId?: number;

  @IsOptional()
  @IsNumber()
  installerId?: number;

  @IsOptional()
  @IsInt()
  @IsIn([0, 1])
  status?: number;
}

export class QueryDeviceDto {
  @IsOptional()
  @Type(() => Number)
  page?: number = 1;

  @IsOptional()
  @Type(() => Number)
  pageSize?: number = 20;

  @IsOptional()
  @IsString()
  keyword?: string;

  @IsOptional()
  @Type(() => Number)
  status?: number;

  @IsOptional()
  @IsString()
  model?: string;

  @IsOptional()
  @Type(() => Number)
  onlineStatus?: number;
}
