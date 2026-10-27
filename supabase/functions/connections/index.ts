import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import {
  createSupabaseConnectionsStore,
  handleConnectionsRequest,
} from './handler.ts';

serveEdgeFunction((deps) => (req) =>
  handleConnectionsRequest(req, {
    verifyToken: deps.verifyToken,
    store: createSupabaseConnectionsStore(deps.admin),
    env: deps.env,
  }),
);
