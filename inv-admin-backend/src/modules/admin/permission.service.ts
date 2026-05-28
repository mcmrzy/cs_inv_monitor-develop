import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RolePermission } from '../../entities/permission.entity';
import { DEFAULT_ROLE_PERMISSIONS } from '../../common/permissions/default-permissions';

@Injectable()
export class PermissionService {
  constructor(
    @InjectRepository(RolePermission)
    private repo: Repository<RolePermission>,
  ) {}

  async seedDefaults() {
    for (const role of [0, 1, 2, 3]) {
      const defaults = DEFAULT_ROLE_PERMISSIONS[role];
      for (const perm of defaults) {
        const existing = await this.repo.findOne({
          where: { role, resource: perm.resource, action: perm.action },
        });
        if (!existing) {
          await this.repo.save(
            this.repo.create({
              role,
              resource: perm.resource,
              action: perm.action,
              is_allowed: true,
            }),
          );
        }
      }
    }
  }

  async getRolePermissions(role: number): Promise<{ resource: string; action: string; is_allowed: boolean }[]> {
    return this.repo.find({ where: { role } });
  }

  async getAllPermissionsConfig(): Promise<Record<number, Record<string, string[]>>> {
    const all = await this.repo.find();
    const config: Record<number, Record<string, string[]>> = {};
    for (const row of all) {
      if (!config[row.role]) config[row.role] = {};
      if (!config[row.role][row.resource]) config[row.role][row.resource] = [];
      if (row.is_allowed) config[row.role][row.resource].push(row.action);
    }
    return config;
  }

  async hasPermission(role: number, resource: string, action: string): Promise<boolean> {
    if (role === 0) return true;
    const perm = await this.repo.findOne({ where: { role, resource, action } });
    return !!perm && perm.is_allowed;
  }

  async setPermission(role: number, resource: string, action: string, isAllowed: boolean) {
    const perm = await this.repo.findOne({ where: { role, resource, action } });
    if (perm) {
      perm.is_allowed = isAllowed;
      return this.repo.save(perm);
    }
    return this.repo.save(
      this.repo.create({ role, resource, action, is_allowed: isAllowed }),
    );
  }

  async batchUpdatePermissions(
    role: number,
    permissions: { resource: string; action: string; is_allowed: boolean }[],
  ) {
    for (const p of permissions) {
      await this.setPermission(role, p.resource, p.action, p.is_allowed);
    }
  }
}
