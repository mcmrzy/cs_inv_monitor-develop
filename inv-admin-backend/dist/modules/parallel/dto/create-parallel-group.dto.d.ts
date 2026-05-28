export declare class CreateParallelGroupDto {
    groupName: string;
    phaseConfig: string;
    masterSn: string;
    slaveSns: string;
    circulatingCurrentThreshold?: number;
    loadBalanceDeviation?: number;
}
export declare class UpdateParallelGroupDto {
    groupName?: string;
    phaseConfig?: string;
    masterSn?: string;
    slaveSns?: string;
    circulatingCurrentThreshold?: number;
    loadBalanceDeviation?: number;
}
export declare class QueryParallelGroupDto {
    page?: number;
    pageSize?: number;
    keyword?: string;
    phaseConfig?: string;
    status?: number;
}
export declare class SyncParamsDto {
    circulatingCurrentThreshold?: number;
    loadBalanceDeviation?: number;
    outputVoltage?: number;
    outputFrequency?: number;
}
