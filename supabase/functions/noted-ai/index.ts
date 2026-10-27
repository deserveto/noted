import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import { createSupabaseNotedAiStore, handleNotedAiRequest } from './handler.ts';

serveEdgeFunction((deps) => (req) =>
  handleNotedAiRequest(req, {
    verifyToken: deps.verifyToken,
    store: createSupabaseNotedAiStore(deps.admin),
    env: deps.env,
  }),
);
