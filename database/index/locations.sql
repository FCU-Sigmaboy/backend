-- ####################################################################
-- ### 索引優化建議 (如果尚未建立)
-- ####################################################################

-- 確保地理位置查詢的效能
CREATE INDEX IF NOT EXISTS idx_locations_coordinates ON public.locations USING GIST(coordinates);
CREATE INDEX IF NOT EXISTS idx_locations_user_primary ON public.locations(user_id, is_primary);

-- 物品查詢優化
CREATE INDEX IF NOT EXISTS idx_items_listing_status ON public.items(listing_status);
CREATE INDEX IF NOT EXISTS idx_items_location_id ON public.items(location_id);

-- 收藏查詢優化
CREATE INDEX IF NOT EXISTS idx_favorites_item_user ON public.favorites(item_id, user_id);
