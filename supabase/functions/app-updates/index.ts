import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import { createSupabaseUpdatesStore, handleAppUpdatesRequest } from './handler.ts';

serveEdgeFunction(deps => req => handleAppUpdatesRequest(req, {
  verifyToken: deps.verifyToken,
  store: createSupabaseUpdatesStore(deps.admin),
}));
