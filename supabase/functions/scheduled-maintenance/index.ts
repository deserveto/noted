import { serveEdgeFunction } from '../_shared/runtime_env.ts';
import {
  createSupabaseScheduledMaintenanceStore,
  handleScheduledMaintenanceRequest,
} from './handler.ts';

serveEdgeFunction((deps) => (req) =>
  handleScheduledMaintenanceRequest(req, {
    cronSecret: deps.env.cronSecret,
    store: createSupabaseScheduledMaintenanceStore(deps.admin),
    storage: deps.admin.storage,
    env: deps.env,
  }),
);
