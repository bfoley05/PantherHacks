-- Venture Local — run in Supabase Dashboard → SQL Editor
-- API URL: https://aqjuqjxmsanrmcpmaroj.supabase.co
--
-- Creates: profiles, visits (cross-device backup), friendships, friend_place_recommendations,
--          friend_recommendation_dismissals (per-user hides on Social)
-- Enable Email auth in Authentication → Providers before testing the app.
-- For instant sign-up in the app: Authentication → Providers → Email → turn OFF “Confirm email”.

-- Optional: backfill profiles for accounts created before this migration
-- INSERT INTO public.profiles (id, display_name)
-- SELECT id, COALESCE(raw_user_meta_data->>'display_name', 'Explorer') FROM auth.users
-- ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT 'Explorer',
  avatar_kind_raw TEXT NOT NULL DEFAULT 'explorer',
  total_xp INT NOT NULL DEFAULT 0,
  home_city_key TEXT,
  home_city_display_name TEXT,
  selected_city_key TEXT,
  pinned_exploration_city_key TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS profiles_total_xp_idx ON public.profiles (total_xp DESC);

CREATE TABLE IF NOT EXISTS public.visits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  osm_id TEXT NOT NULL,
  city_key TEXT NOT NULL,
  discovered_at TIMESTAMPTZ NOT NULL,
  explorer_note TEXT,
  UNIQUE (user_id, osm_id)
);

CREATE INDEX IF NOT EXISTS visits_user_id_idx ON public.visits (user_id);

CREATE TABLE IF NOT EXISTS public.friendships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'accepted')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (requester_id, addressee_id),
  CHECK (requester_id <> addressee_id)
);

CREATE INDEX IF NOT EXISTS friendships_requester_idx ON public.friendships (requester_id);
CREATE INDEX IF NOT EXISTS friendships_addressee_idx ON public.friendships (addressee_id);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_authenticated ON public.profiles;
CREATE POLICY profiles_select_authenticated
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS visits_all_own ON public.visits;
CREATE POLICY visits_all_own
  ON public.visits FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS friendships_select_participants ON public.friendships;
CREATE POLICY friendships_select_participants
  ON public.friendships FOR SELECT
  TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS friendships_insert_as_requester ON public.friendships;
CREATE POLICY friendships_insert_as_requester
  ON public.friendships FOR INSERT
  TO authenticated
  WITH CHECK (requester_id = auth.uid() AND requester_id <> addressee_id);

DROP POLICY IF EXISTS friendships_update_addressee_accept ON public.friendships;
CREATE POLICY friendships_update_addressee_accept
  ON public.friendships FOR UPDATE
  TO authenticated
  USING (addressee_id = auth.uid() AND status = 'pending')
  WITH CHECK (status = 'accepted');

DROP POLICY IF EXISTS friendships_delete_participants ON public.friendships;
CREATE POLICY friendships_delete_participants
  ON public.friendships FOR DELETE
  TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.visits TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.friendships TO authenticated;

-- Friend place recommendations (visible to accepted friends + author; Social tab + map share)
CREATE TABLE IF NOT EXISTS public.friend_place_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  osm_id TEXT NOT NULL,
  city_key TEXT NOT NULL,
  place_name TEXT NOT NULL DEFAULT '',
  category_raw TEXT NOT NULL DEFAULT '',
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  recommended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (from_user_id, osm_id)
);

ALTER TABLE public.friend_place_recommendations
  ADD COLUMN IF NOT EXISTS category_raw TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS friend_place_recommendations_from_idx
  ON public.friend_place_recommendations (from_user_id);
CREATE INDEX IF NOT EXISTS friend_place_recommendations_time_idx
  ON public.friend_place_recommendations (recommended_at DESC);

ALTER TABLE public.friend_place_recommendations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS friend_rec_select ON public.friend_place_recommendations;
CREATE POLICY friend_rec_select
  ON public.friend_place_recommendations FOR SELECT
  TO authenticated
  USING (
    from_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.friendships f
      WHERE f.status = 'accepted'
        AND (
          (f.requester_id = auth.uid() AND f.addressee_id = friend_place_recommendations.from_user_id)
          OR (f.addressee_id = auth.uid() AND f.requester_id = friend_place_recommendations.from_user_id)
        )
    )
  );

DROP POLICY IF EXISTS friend_rec_insert_own ON public.friend_place_recommendations;
CREATE POLICY friend_rec_insert_own
  ON public.friend_place_recommendations FOR INSERT
  TO authenticated
  WITH CHECK (from_user_id = auth.uid());

DROP POLICY IF EXISTS friend_rec_update_own ON public.friend_place_recommendations;
CREATE POLICY friend_rec_update_own
  ON public.friend_place_recommendations FOR UPDATE
  TO authenticated
  USING (from_user_id = auth.uid())
  WITH CHECK (from_user_id = auth.uid());

DROP POLICY IF EXISTS friend_rec_delete_own ON public.friend_place_recommendations;
CREATE POLICY friend_rec_delete_own
  ON public.friend_place_recommendations FOR DELETE
  TO authenticated
  USING (from_user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.friend_place_recommendations TO authenticated;

-- Per-user dismissals: hiding a friend’s recommendation on Social (does not delete the friend’s row).
CREATE TABLE IF NOT EXISTS public.friend_recommendation_dismissals (
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  recommendation_id UUID NOT NULL REFERENCES public.friend_place_recommendations (id) ON DELETE CASCADE,
  dismissed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, recommendation_id)
);

CREATE INDEX IF NOT EXISTS friend_rec_dismissals_user_idx
  ON public.friend_recommendation_dismissals (user_id);

ALTER TABLE public.friend_recommendation_dismissals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS friend_rec_dismissal_select_own ON public.friend_recommendation_dismissals;
CREATE POLICY friend_rec_dismissal_select_own
  ON public.friend_recommendation_dismissals FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS friend_rec_dismissal_insert_visible_rec ON public.friend_recommendation_dismissals;
CREATE POLICY friend_rec_dismissal_insert_visible_rec
  ON public.friend_recommendation_dismissals FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.friend_place_recommendations r
      WHERE r.id = friend_recommendation_dismissals.recommendation_id
        AND (
          r.from_user_id = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.friendships f
            WHERE f.status = 'accepted'
              AND (
                (f.requester_id = auth.uid() AND f.addressee_id = r.from_user_id)
                OR (f.addressee_id = auth.uid() AND f.requester_id = r.from_user_id)
              )
          )
        )
    )
  );

DROP POLICY IF EXISTS friend_rec_dismissal_delete_own ON public.friend_recommendation_dismissals;
CREATE POLICY friend_rec_dismissal_delete_own
  ON public.friend_recommendation_dismissals FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.friend_recommendation_dismissals TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_kind_raw)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', 'Explorer'),
    'explorer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();
