DO $$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_listing_status') THEN
            CREATE INDEX idx_items_listing_status ON public.items(listing_status)
                WHERE listing_status = true;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_id_listing_status') THEN
            CREATE INDEX idx_items_id_listing_status ON public.items(id, listing_status)
                WHERE listing_status = true;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_locations_user_primary') THEN
            CREATE INDEX idx_locations_user_primary ON public.locations(user_id, is_primary);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_locations_coordinates_gist') THEN
            CREATE INDEX idx_locations_coordinates_gist ON public.locations USING GIST(coordinates);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_favorites_item_user') THEN
            CREATE INDEX idx_favorites_item_user ON public.favorites(item_id, user_id);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_user_id') THEN
            CREATE INDEX idx_items_user_id ON public.items(user_id);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_items_sub_category') THEN
            CREATE INDEX idx_items_sub_category ON public.items(sub_category_id);
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_sub_categories_main') THEN
            CREATE INDEX idx_sub_categories_main ON public.sub_categories(main_category_id);
        END IF;
    END $$;