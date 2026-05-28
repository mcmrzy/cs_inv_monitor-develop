import { IsString, IsOptional, IsNumber, IsIn, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateParallelGroupDto {
  @IsString()
  groupName: string;

  @IsString()
  @IsIn(['single', 'three_phase'])
  phaseConfig: string;

  @IsString()
  masterSn: string;

  @IsString()
  slaveSns: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  circulatingCurrentThreshold?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  @Type(() => Number)
  loadBalanceDeviation?: number;
}

export class UpdateParallelGroupDto {
  @IsOptional()
  @IsString()
  groupName?: string;

  @IsOptional()
  @IsString()
  @IsIn(['single', 'three_phase'])
  phaseConfig?: string;

  @IsOptional()
  @IsString()
  masterSn?: string;

  @IsOptional()
  @IsString()
  slaveSns?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  circulatingCurrentThreshold?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  @Type(() => Number)
  loadBalanceDeviation?: number;
}

export class QueryParallelGroupDto {
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
  @IsString()
  phaseConfig?: string;

  @IsOptional()
  @Type(() => Number)
  status?: number;
}

export class SyncParamsDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  circulatingCurrentThreshold?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(100)
  @Type(() => Number)
  loadBalanceDeviation?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  outputVoltage?: number;

  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  outputFrequency?: number;
}
