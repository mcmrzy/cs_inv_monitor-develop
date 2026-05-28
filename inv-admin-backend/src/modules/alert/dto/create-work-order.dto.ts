import { Type } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, IsInt, Min, Max } from 'class-validator';

export class CreateWorkOrderDto {
  @IsNotEmpty({ message: '工单标题不能为空' })
  @IsString()
  title: string;

  @IsNotEmpty({ message: '工单描述不能为空' })
  @IsString()
  description: string;

  @IsOptional()
  @IsString()
  deviceSn?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  stationId?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  assignedTo?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(4)
  priority?: number = 1;

  @IsOptional()
  @IsString()
  templateType?: string;
}
