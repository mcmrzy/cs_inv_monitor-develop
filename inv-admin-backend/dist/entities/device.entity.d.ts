import { User } from './user.entity';
import { Station } from './station.entity';
export declare class Device {
    id: number;
    sn: string;
    model: string;
    rated_power: number;
    firmware_version: string;
    hardware_version: string;
    mac_address: string;
    station_id: number | null;
    station: Station | null;
    user_id: number;
    owner: User | null;
    installer_id: number;
    installer: User | null;
    status: number;
    last_online_at: Date;
    ip_address: string | null;
    created_at: Date;
    updated_at: Date;
    deleted_at: Date;
}
