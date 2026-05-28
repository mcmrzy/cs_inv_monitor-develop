export declare class DeviceServerProxyService {
    private readonly logger;
    private readonly goAdminBaseUrl;
    private readonly commandPath;
    sendCommand(sn: string, commandName: string, params: Record<string, any>, reqId: string): Promise<any>;
    waitForAck(reqId: string, timeoutMs?: number): Promise<any>;
    private httpPost;
    private httpGet;
    private sleep;
}
