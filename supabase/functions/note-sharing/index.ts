import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import {
  createSupabaseNoteSharingStore,
  handleNoteSharingRequest,
} from './handler.ts';

serveEdgeFunction((deps) => (req) =>
  handleNoteSharingRequest(req, {
    verifyToken: deps.verifyToken,
    store: createSupabaseNoteSharingStore(deps.admin),
    storage: deps.admin.storage,
    env: deps.env,
  }),
);
