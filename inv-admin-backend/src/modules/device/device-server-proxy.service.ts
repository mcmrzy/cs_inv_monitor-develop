import { Injectable, Logger } from '@nestjs/common';
import * as http from 'http';

@Injectable()
export class DeviceServerProxyService {
  private readonly logger = new Logger(DeviceServerProxyService.name);
  private readonly goAdminBaseUrl = 'http://localhost:8080/admin/api';
  private readonly commandPath = '/devices';

  async sendCommand(sn: string, commandName: string, params: Record<string, any>, reqId: string): Promise<any> {
    const url = `${this.goAdminBaseUrl}${this.commandPath}/${encodeURIComponent(sn)}/command`;
    const body = JSON.stringify({
      sn,
      command: commandName,
      params,
      reqId,
    });

    this.logger.log(`Sending command to Go server: ${url} - ${body}`);

    return this.httpPost(url, body);
  }

  async waitForAck(reqId: string, timeoutMs: number = 12000): Promise<any> {
    const startTime = Date.now();
    const pollInterval = 3000;
    const maxRetries = Math.ceil(timeoutMs / pollInterval);
    let lastError: Error | null = null;

    for (let i = 0; i < maxRetries; i++) {
      const elapsed = Date.now() - startTime;
      if (elapsed >= timeoutMs) {
        break;
      }

      try {
        const url = `${this.goAdminBaseUrl}/commands/${reqId}/status`;
        const result = await this.httpGet(url);

        if (result && result.status === 'completed') {
          return result;
        }

        if (result && result.status === 'failed') {
          throw new Error(result.message || 'Command execution failed on device');
        }

        if (result && result.status === 'ack_received') {
          return result;
        }
      } catch (err: any) {
        lastError = err;
      }

      const remaining = timeoutMs - (Date.now() - startTime);
      if (remaining > 0) {
        await this.sleep(Math.min(pollInterval, remaining));
      }
    }

    if (lastError) {
      throw lastError;
    }

    throw new Error(`Command ACK timeout after ${timeoutMs}ms`);
  }

  private httpPost(url: string, body: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const urlObj = new URL(url);
      const options: http.RequestOptions = {
        hostname: urlObj.hostname,
        port: urlObj.port,
        path: urlObj.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: 10000,
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            try {
              resolve(JSON.parse(data));
            } catch {
              resolve({ raw: data });
            }
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          }
        });
      });

      req.on('error', (err) => {
        reject(err);
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });

      req.write(body);
      req.end();
    });
  }

  private httpGet(url: string): Promise<any> {
    return new Promise((resolve, reject) => {
      const urlObj = new URL(url);
      const options: http.RequestOptions = {
        hostname: urlObj.hostname,
        port: urlObj.port,
        path: urlObj.pathname + urlObj.search,
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
        timeout: 5000,
      };

      const req = http.request(options, (res) => {
        let data = '';
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            try {
              resolve(JSON.parse(data));
            } catch {
              resolve({ raw: data });
            }
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${data}`));
          }
        });
      });

      req.on('error', (err) => {
        reject(err);
      });

      req.on('timeout', () => {
        req.destroy();
        reject(new Error('Request timeout'));
      });

      req.end();
    });
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
