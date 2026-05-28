export declare class CreateDeviceDto {
    sn: string;
    model?: string;
    ratedPower?: number;
    firmwareVersion?: string;
    stationId?: number;
    userId?: number;
    installerId?: number;
}
export declare class UpdateDeviceDto {
    model?: string;
    ratedPower?: number;
    firmwareVersion?: string;
    stationId?: number;
    userId?: number;
    installerId?: number;
    status?: number;
}
export declare class QueryDeviceDto {
    page?: number;
    pageSize?: number;
    keyword?: string;
    status?: number;
    model?: string;
    onlineStatus?: number;
}
