import { AppError } from './cors.ts';

export async function claimNoteDeletion(admin: any, noteId: string, ownerId: string, before?: string): Promise<{claimed: boolean; note: any}> {
  const { data, error } = await admin.rpc('audit_claim_note_deletion', { p_note_id: noteId, p_owner_id: ownerId, p_before: before ?? null });
  if (error || !data) throw new AppError('internal', error?.message ?? 'Could not claim note deletion.');
  return data;
}
export async function finalizeNoteDeletion(admin: any, noteId: string, ownerId: string): Promise<boolean> {
  const { data, error } = await admin.rpc('audit_finalize_note_deletion', { p_note_id: noteId, p_owner_id: ownerId });
  if (error) throw new AppError('internal', error.message);
  return Boolean(data);
}
