-- Auto-create public.users record when auth.users is created
-- Date: 2025-11-02
-- Purpose: Sync OAuth user signup to public.users table

-- Create trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- When auth.users gets a new record, create corresponding public.users record
    INSERT INTO public.users (id, nickname, profile_picture_url, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email, 'User_' || substring(NEW.id::text, 1, 8)),
        NEW.raw_user_meta_data->>'avatar_url',
        NEW.created_at,
        NEW.updated_at
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Backfill existing auth.users to public.users (if missing)
INSERT INTO public.users (id, nickname, profile_picture_url, created_at, updated_at)
SELECT
    id,
    COALESCE(raw_user_meta_data->>'name', email, 'User_' || substring(id::text, 1, 8)),
    raw_user_meta_data->>'avatar_url',
    created_at,
    updated_at
FROM auth.users
WHERE NOT EXISTS (
    SELECT 1 FROM public.users WHERE public.users.id = auth.users.id
)
ON CONFLICT (id) DO NOTHING;
