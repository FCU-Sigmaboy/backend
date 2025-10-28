DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='main_categories' AND column_name='icon'
    ) THEN
        ALTER TABLE main_categories ADD COLUMN icon TEXT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name='main_categories' AND column_name='color'
    ) THEN
        ALTER TABLE main_categories ADD COLUMN color TEXT;
    END IF;
END $$;

