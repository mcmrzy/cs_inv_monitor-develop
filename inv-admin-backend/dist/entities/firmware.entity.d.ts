export declare class Firmware {
    id: number;
    model: string;
    version: string;
    file_url: string;
    file_size: number;
    file_md5: string;
    file_sha256: string | null;
    changelog: string;
    is_force: boolean;
    status: number;
    created_at: Date;
    uploaded_by: number;
}
