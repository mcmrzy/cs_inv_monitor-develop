import { Repository } from 'typeorm';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';
export declare class GeoLocationService {
    private deviceRepo;
    private stationRepo;
    private readonly logger;
    private readonly processedIPs;
    constructor(deviceRepo: Repository<Device>, stationRepo: Repository<Station>);
    autoSyncStationCoords(): Promise<void>;
    private updateStationCoords;
    private geolocateIP;
    private tryIpApiCom;
    private tryPConline;
    private tryBaiduIp;
    private tryAmapCity;
}
