import { SetMetadata } from '@nestjs/common';

export const REQUIRE_REAUTH_KEY = 'require_reauth';

export const RequireReauth = () => SetMetadata(REQUIRE_REAUTH_KEY, true);
