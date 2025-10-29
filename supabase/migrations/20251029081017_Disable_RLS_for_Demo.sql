-- =============================================
-- 停用 RLS 權限控制 - Demo 環境專用
-- 建立日期: 2025-10-29
-- 警告：此檔案僅適用於 Demo/測試環境，正式環境請勿使用！
-- =============================================

-- 顯示執行訊息
DO $$
BEGIN
    RAISE NOTICE '開始停用所有資料表的 RLS 權限控制...';
END $$;

-- =============================================
-- 停用所有主要資料表的 RLS
-- =============================================

-- 1. 使用者相關表
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations DISABLE ROW LEVEL SECURITY;

-- 2. 物品相關表
ALTER TABLE public.items DISABLE ROW LEVEL SECURITY;

-- 3. 交易相關表
ALTER TABLE public.transactions DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_logs DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings DISABLE ROW LEVEL SECURITY;

-- 4. 社交功能表
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.following DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites DISABLE ROW LEVEL SECURITY;

-- =============================================
-- 授予完整權限給 anon 和 authenticated 角色
-- =============================================

-- 使用者相關表權限
GRANT ALL ON public.users TO anon, authenticated;
GRANT ALL ON public.profiles TO anon, authenticated;
GRANT ALL ON public.locations TO anon, authenticated;

-- 物品相關表權限
GRANT ALL ON public.items TO anon, authenticated;

-- 交易相關表權限
GRANT ALL ON public.transactions TO anon, authenticated;
GRANT ALL ON public.point_logs TO anon, authenticated;
GRANT ALL ON public.ratings TO anon, authenticated;

-- 社交功能表權限
GRANT ALL ON public.conversations TO anon, authenticated;
GRANT ALL ON public.conversation_messages TO anon, authenticated;
GRANT ALL ON public.following TO anon, authenticated;
GRANT ALL ON public.favorites TO anon, authenticated;

-- =============================================
-- 序列權限設定
-- =============================================

-- 授予序列使用權限
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- 特別處理主要序列
GRANT USAGE, SELECT ON SEQUENCE locations_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE items_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE transactions_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE point_logs_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE ratings_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE conversations_id_seq TO anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE conversation_messages_id_seq TO anon, authenticated;

-- =============================================
-- Storage 權限設定（為 Demo 開放所有存取）
-- =============================================

-- 移除現有的 storage 限制性政策
DO $$
DECLARE
    pol RECORD;
BEGIN
    -- 刪除 avatars bucket 的限制性政策
    FOR pol IN SELECT policyname FROM pg_policies
               WHERE schemaname = 'storage'
               AND tablename = 'objects'
               AND policyname NOT LIKE '%accessible to everyone%'
               AND policyname LIKE '%avatar%'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;

    -- 刪除 items bucket 的限制性政策
    FOR pol IN SELECT policyname FROM pg_policies
               WHERE schemaname = 'storage'
               AND tablename = 'objects'
               AND policyname NOT LIKE '%accessible to everyone%'
               AND policyname LIKE '%item%'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;
END $$;

-- 建立 Demo 專用的開放 storage 政策
CREATE POLICY "Demo - Anyone can upload avatars"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "Demo - Anyone can update avatars"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'avatars');

CREATE POLICY "Demo - Anyone can delete avatars"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'avatars');

CREATE POLICY "Demo - Anyone can upload item images"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'items');

CREATE POLICY "Demo - Anyone can update item images"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'items');

CREATE POLICY "Demo - Anyone can delete item images"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'items');

-- =============================================
-- 建立 Demo 專用的輔助函數
-- =============================================

-- 建立一個不需要認證的搜尋函數版本
CREATE OR REPLACE FUNCTION public.search_items_demo(
    p_distance_range_km INT DEFAULT NULL,
    p_main_category_id INT DEFAULT NULL,
    p_sub_category_id INT DEFAULT NULL,
    p_keyword TEXT DEFAULT NULL,
    p_user_id UUID DEFAULT NULL,
    p_page INT DEFAULT 1,
    p_size INT DEFAULT 20,
    p_sort_by TEXT DEFAULT 'created_at',
    p_sort_direction TEXT DEFAULT 'desc'
)
RETURNS TABLE (
    item_id BIGINT,
    title TEXT,
    image_url TEXT,
    price INT,
    distance_km NUMERIC,
    formatted_address TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    favorites_count BIGINT,
    "user" JSON
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER  -- 以函數擁有者權限執行
AS $$
DECLARE
    v_offset INT;
BEGIN
    -- 計算 offset
    v_offset := (p_page - 1) * p_size;

    -- 簡化的搜尋邏輯，不需要位置驗證
    RETURN QUERY
    SELECT
        i.id,
        i.title,
        i.image_urls[1],
        i.price,
        0::NUMERIC AS distance_km,  -- Demo 模式固定距離為 0
        l.formatted_address,
        i.created_at,
        i.updated_at,
        COALESCE(fav.count, 0),
        json_build_object(
            'id', u.id,
            'nickname', u.nickname,
            'profile_picture_url', u.profile_picture_url
        )
    FROM public.items i
    LEFT JOIN public.users u ON i.user_id = u.id
    LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
    LEFT JOIN public.locations l ON i.location_id = l.id
    LEFT JOIN (
        SELECT item_id, count(*)
        FROM public.favorites
        GROUP BY item_id
    ) fav ON i.id = fav.item_id
    WHERE i.listing_status = TRUE
      AND (p_main_category_id IS NULL OR sc.main_category_id = p_main_category_id)
      AND (p_sub_category_id IS NULL OR i.sub_category_id = p_sub_category_id)
      AND (p_user_id IS NULL OR i.user_id = p_user_id)
      AND (p_keyword IS NULL OR (i.title ILIKE '%' || p_keyword || '%' OR i.tags @> ARRAY[p_keyword]))
    ORDER BY
        CASE
            WHEN LOWER(p_sort_by) = 'price' AND LOWER(p_sort_direction) = 'asc' THEN i.price
        END ASC,
        CASE
            WHEN LOWER(p_sort_by) = 'price' AND LOWER(p_sort_direction) = 'desc' THEN i.price
        END DESC,
        CASE
            WHEN LOWER(p_sort_by) = 'created_at' AND LOWER(p_sort_direction) = 'asc' THEN i.created_at
        END ASC,
        i.created_at DESC  -- 預設排序
    LIMIT p_size OFFSET v_offset;
END;
$$;

-- =============================================
-- 驗證設定結果
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '=== RLS 停用狀態驗證 ===';
    RAISE NOTICE '以下資料表的 RLS 已停用：';
    RAISE NOTICE '- users, profiles, locations';
    RAISE NOTICE '- items, transactions, point_logs, ratings';
    RAISE NOTICE '- conversations, conversation_messages';
    RAISE NOTICE '- following, favorites';
    RAISE NOTICE '';
    RAISE NOTICE '=== 權限授予完成 ===';
    RAISE NOTICE '已授予 anon 和 authenticated 角色完整權限';
    RAISE NOTICE '';
    RAISE NOTICE '=== Storage 權限開放 ===';
    RAISE NOTICE 'avatars 和 items bucket 已開放所有操作';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  警告：這是 Demo 環境設定，正式環境請勿使用！';
    RAISE NOTICE '⚠️  記得在測試完成後恢復原始 RLS 設定！';
END $$;

-- =============================================
-- 建立恢復 RLS 的 SQL 註解說明
-- =============================================

/*
要恢復原始 RLS 設定，請執行以下 SQL：

-- 重新啟用 RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.following ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

-- 撤銷過度權限
REVOKE ALL ON public.users FROM anon;
REVOKE ALL ON public.profiles FROM anon;
REVOKE ALL ON public.locations FROM anon;
REVOKE ALL ON public.items FROM anon;
REVOKE ALL ON public.transactions FROM anon;
REVOKE ALL ON public.point_logs FROM anon;
REVOKE ALL ON public.ratings FROM anon;
REVOKE ALL ON public.conversations FROM anon;
REVOKE ALL ON public.conversation_messages FROM anon;
REVOKE ALL ON public.following FROM anon;
REVOKE ALL ON public.favorites FROM anon;

-- 重新執行 20251025101010_setup_row_level_security.sql 和 20251025180327_setup_storage_rls.sql
*/
