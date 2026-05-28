import { IsString, IsArray, IsInt, IsOptional, IsIn, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateOtaTaskDto {
  @IsString()
  name: string;

  @Type(() => Number)
  @IsInt()
  firmwareId: number;

  @IsArray()
  @IsString({ each: true })
  deviceSns: string[];

  @IsOptional()
  @IsString()
  @IsIn(['all_at_once', 'percentage', 'batch'])
  pushStrategy?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  pushPercentage?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  batchSize?: number;
}
