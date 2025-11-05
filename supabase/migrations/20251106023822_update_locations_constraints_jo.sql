-- =============================================
-- 更新 locations 表的約束條件
-- 日期: 2025-11-06
--
-- 變更內容:
-- 1. 移除"其他"地點類型，只允許"家"和"公司"
-- 2. 每位用戶只能有一個 is_primary=true 的地點（全局限制）
-- 3. 每位用戶每種類型只能有一個地點（最多 2 個地點）
-- =============================================

-- 1. 更新現有的"其他"類型地點為"家"（如果用戶沒有"家"）或刪除
DO $$
DECLARE
    loc RECORD;
BEGIN
    -- 處理所有"其他"類型的地點
    FOR loc IN
        SELECT l.id, l.user_id
        FROM public.locations l
        WHERE l.type = '其他'
    LOOP
        -- 檢查該用戶是否已有"家"
        IF NOT EXISTS (
            SELECT 1 FROM public.locations
            WHERE user_id = loc.user_id AND type = '家'
        ) THEN
            -- 沒有"家"，將"其他"改為"家"
            UPDATE public.locations
            SET type = '家', updated_at = now()
            WHERE id = loc.id;

            RAISE NOTICE '將用戶 % 的地點 % 從"其他"改為"家"', loc.user_id, loc.id;
        ELSE
            -- 已有"家"，刪除"其他"地點
            -- 但首先需要檢查是否有 items 引用此地點
            IF EXISTS (SELECT 1 FROM public.items WHERE location_id = loc.id) THEN
                -- 重新指派 items 到用戶的"家"地點，如果沒有則指派到"公司"，如果都沒有則建立"家"
                DECLARE
                    new_location_id BIGINT;
                BEGIN
                    -- 優先找"家"
                    SELECT id INTO new_location_id FROM public.locations WHERE user_id = loc.user_id AND type = '家' LIMIT 1;
                    IF new_location_id IS NULL THEN
                        -- 沒有"家"，找"公司"
                        SELECT id INTO new_location_id FROM public.locations WHERE user_id = loc.user_id AND type = '公司' LIMIT 1;
                    END IF;
                    IF new_location_id IS NULL THEN
                        -- 都沒有，建立一個"家"
                        INSERT INTO public.locations (user_id, type, is_primary, created_at, updated_at)
                        VALUES (loc.user_id, '家', false, now(), now())
                        RETURNING id INTO new_location_id;
                        RAISE NOTICE '為用戶 % 建立新的"家"地點 %', loc.user_id, new_location_id;
                    END IF;
                    -- 更新 items 的 location_id
                    UPDATE public.items SET location_id = new_location_id WHERE location_id = loc.id;
                    RAISE NOTICE '將用戶 % 的 items 從地點 % 重新指派到地點 %', loc.user_id, loc.id, new_location_id;
                    -- 現在可以安全刪除"其他"地點
                    DELETE FROM public.locations WHERE id = loc.id;
                    RAISE NOTICE '刪除用戶 % 的"其他"地點 %', loc.user_id, loc.id;
                END;
            ELSE
                -- 沒有 items 引用，直接刪除
                DELETE FROM public.locations WHERE id = loc.id;
                RAISE NOTICE '刪除用戶 % 的"其他"地點 %', loc.user_id, loc.id;
            END IF;
    END LOOP;
END $$;

-- 2. 處理每種類型只保留一個地點的邏輯
DO $$
DECLARE
    user_rec RECORD;
    loc_rec RECORD;
    keep_id BIGINT;
    has_cleanup_failures BOOLEAN := false;
    failure_details TEXT := '';
BEGIN
    -- 對每個用戶，檢查每種類型是否有多個地點
    FOR user_rec IN
        SELECT DISTINCT user_id FROM public.locations
    LOOP
        -- 處理"家"類型
        SELECT id INTO keep_id
        FROM public.locations
        WHERE user_id = user_rec.user_id AND type = '家'
        ORDER BY is_primary DESC, created_at ASC
        LIMIT 1;

        IF keep_id IS NOT NULL THEN
            -- 刪除其他"家"地點（如果沒有被 items 引用）
            FOR loc_rec IN
                SELECT id FROM public.locations
                WHERE user_id = user_rec.user_id AND type = '家' AND id != keep_id
            LOOP
                IF NOT EXISTS (SELECT 1 FROM public.items WHERE location_id = loc_rec.id) THEN
                    DELETE FROM public.locations WHERE id = loc_rec.id;
                    RAISE NOTICE '刪除用戶 % 的重複"家"地點 %', user_rec.user_id, loc_rec.id;
                ELSE
                    has_cleanup_failures := true;
                    failure_details := failure_details || format('用戶 %s 的地點 %s (類型: 家) 被 items 引用，無法刪除。', user_rec.user_id, loc_rec.id) || E'\n';
                    RAISE NOTICE '用戶 % 的地點 % 被 items 引用，無法刪除', user_rec.user_id, loc_rec.id;
                END IF;
            END LOOP;
        END IF;

        -- 處理"公司"類型
        keep_id := NULL;
        SELECT id INTO keep_id
        FROM public.locations
        WHERE user_id = user_rec.user_id AND type = '公司'
        ORDER BY is_primary DESC, created_at ASC
        LIMIT 1;

        IF keep_id IS NOT NULL THEN
            -- 刪除其他"公司"地點（如果沒有被 items 引用）
            FOR loc_rec IN
                SELECT id FROM public.locations
                WHERE user_id = user_rec.user_id AND type = '公司' AND id != keep_id
            LOOP
                IF NOT EXISTS (SELECT 1 FROM public.items WHERE location_id = loc_rec.id) THEN
                    DELETE FROM public.locations WHERE id = loc_rec.id;
                    RAISE NOTICE '刪除用戶 % 的重複"公司"地點 %', user_rec.user_id, loc_rec.id;
                ELSE
                    has_cleanup_failures := true;
                    failure_details := failure_details || format('用戶 %s 的地點 %s (類型: 公司) 被 items 引用，無法刪除。', user_rec.user_id, loc_rec.id) || E'\n';
                    RAISE NOTICE '用戶 % 的地點 % 被 items 引用，無法刪除', user_rec.user_id, loc_rec.id;
                END IF;
            END LOOP;
        END IF;
    END LOOP;
    
    -- 如果有清理失敗的情況，拋出錯誤並中止遷移
    IF has_cleanup_failures THEN
        RAISE EXCEPTION E'遷移失敗：無法清理重複的地點資料，因為這些地點被 items 引用。\n請先手動處理以下地點的 items 引用關係，再重新執行遷移：\n%', failure_details;
    END IF;
END $$;

-- 3. 確保每位用戶只有一個 is_primary=true 的地點
DO $$
DECLARE
    user_rec RECORD;
    primary_count INT;
    keep_primary_id BIGINT;
BEGIN
    FOR user_rec IN
        SELECT DISTINCT user_id FROM public.locations
    LOOP
        -- 檢查該用戶有幾個主要地點
        SELECT COUNT(*) INTO primary_count
        FROM public.locations
        WHERE user_id = user_rec.user_id AND is_primary = true;

        IF primary_count = 0 THEN
            -- 沒有主要地點，設定第一個地點為主要
            UPDATE public.locations
            SET is_primary = true, updated_at = now()
            WHERE id = (
                SELECT id FROM public.locations
                WHERE user_id = user_rec.user_id
                ORDER BY type = '家' DESC, created_at ASC
                LIMIT 1
            );
            RAISE NOTICE '用戶 % 沒有主要地點，已設定第一個地點為主要', user_rec.user_id;

        ELSIF primary_count > 1 THEN
            -- 有多個主要地點，只保留一個
            SELECT id INTO keep_primary_id
            FROM public.locations
            WHERE user_id = user_rec.user_id AND is_primary = true
            ORDER BY type = '家' DESC, created_at ASC
            LIMIT 1;

            -- 將其他主要地點設為非主要
            UPDATE public.locations
            SET is_primary = false, updated_at = now()
            WHERE user_id = user_rec.user_id
                AND is_primary = true
                AND id != keep_primary_id;

            RAISE NOTICE '用戶 % 有多個主要地點，已保留地點 % 為主要', user_rec.user_id, keep_primary_id;
        END IF;
    END LOOP;
END $$;

-- 4. 更新 CHECK 約束：移除"其他"類型
ALTER TABLE public.locations
DROP CONSTRAINT IF EXISTS locations_type_check;

ALTER TABLE public.locations
ADD CONSTRAINT locations_type_check
CHECK (type IN ('家', '公司'));

-- 5. 新增唯一約束：每位用戶每種類型只能有一個地點
ALTER TABLE public.locations
DROP CONSTRAINT IF EXISTS unique_user_location_type;

ALTER TABLE public.locations
ADD CONSTRAINT unique_user_location_type
UNIQUE (user_id, type);

-- 6. 新增唯一約束：每位用戶只能有一個 is_primary=true 的地點
-- 使用部分唯一索引來實現此約束
DROP INDEX IF EXISTS unique_user_primary_location;

CREATE UNIQUE INDEX unique_user_primary_location
ON public.locations (user_id)
WHERE is_primary = true;

-- 7. 新增註釋
COMMENT ON CONSTRAINT locations_type_check ON public.locations IS
'地點類型只能是「家」或「公司」';

COMMENT ON CONSTRAINT unique_user_location_type ON public.locations IS
'每位用戶每種類型只能有一個地點';

COMMENT ON INDEX unique_user_primary_location IS
'每位用戶只能有一個主要地點 (is_primary=true)';

-- 8. 記錄變更
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ locations 表約束更新完成';
    RAISE NOTICE '   - 移除"其他"類型，只允許"家"和"公司"';
    RAISE NOTICE '   - 每位用戶每種類型只能有一個地點';
    RAISE NOTICE '   - 每位用戶全局只能有一個 is_primary=true 的地點';
    RAISE NOTICE '========================================';
END $$;

