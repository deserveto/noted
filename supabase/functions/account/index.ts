import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import { createSupabaseAccountStore, handleAccountRequest } from './handler.ts';

serveEdgeFunction((deps) => (req) =>
  handleAccountRequest(req, {
    verifyToken: deps.verifyToken,
    verifyPassword: deps.verifyPassword,
    store: createSupabaseAccountStore(deps.admin),
    storage: deps.admin.storage,
  }),
);
