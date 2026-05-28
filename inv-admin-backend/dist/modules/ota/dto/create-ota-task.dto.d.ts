export declare class CreateOtaTaskDto {
    name: string;
    firmwareId: number;
    deviceSns: string[];
    pushStrategy?: string;
    pushPercentage?: number;
    batchSize?: number;
}
