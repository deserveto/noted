CREATE TABLE public.ai_flashcard_decks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  cards jsonb NOT NULL CHECK (jsonb_typeof(cards) = 'array' AND jsonb_array_length(cards) BETWEEN 1 AND 480),
  source_note_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_flashcard_decks ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_flashcard_decks_own ON public.ai_flashcard_decks FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_flashcard_decks TO authenticated;

CREATE TRIGGER audit_guard_account_writes BEFORE INSERT OR UPDATE ON public.ai_flashcard_decks FOR EACH ROW EXECUTE FUNCTION public.audit_guard_account_writes();

