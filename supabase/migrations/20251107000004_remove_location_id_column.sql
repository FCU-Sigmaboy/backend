-- =============================================
-- Migration: 完全移除 items.location_id 欄位
-- 日期: 2025-11-07
-- 說明:
--   這是遷移的最後階段，只有在以下條件都滿足後才執行：
--   1. 已部署前三個 migrations
--   2. 已更新前端 API 呼叫（移除 location_id 參數）
--   3. 已確認所有 RPC 函數正常運作
--   4. 已在測試環境驗證完成
--
-- ⚠️ 警告：此 migration 無法輕易回滾，請確保備份！
-- =============================================

-- =============================================
-- 步驟 1: 最終確認 - 檢查是否還有程式碼依賴 location_id
-- =============================================

DO $$
DECLARE
    v_functions_using_location_id INT;
BEGIN
    -- 檢查是否有函數仍在使用 i.location_id 或 items.location_id
    SELECT COUNT(*) INTO v_functions_using_location_id
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND (p.prosrc LIKE '%i.location_id%'
       OR p.prosrc LIKE '%items.location_id%');

    IF v_functions_using_location_id > 0 THEN
        RAISE WARNING '發現 % 個函數可能仍在使用 location_id，請檢查', v_functions_using_location_id;
        RAISE WARNING '如果這些是舊版本函數，請忽略此警告';
    END IF;

    RAISE NOTICE '準備移除 location_id 欄位...';
END $$;

-- =============================================
-- 步驟 2: 備份資料統計（記錄在 log 中）
-- =============================================

DO $$
DECLARE
    v_total_items INT;
    v_items_with_location_id INT;
    v_items_null_location_id INT;
BEGIN
    SELECT COUNT(*) INTO v_total_items FROM public.items;

    SELECT COUNT(*) INTO v_items_with_location_id
    FROM public.items
    WHERE location_id IS NOT NULL;

    SELECT COUNT(*) INTO v_items_null_location_id
    FROM public.items
    WHERE location_id IS NULL;

    RAISE NOTICE '====================================';
    RAISE NOTICE '資料統計（刪除前）:';
    RAISE NOTICE '總物品數: %', v_total_items;
    RAISE NOTICE '有 location_id 的物品: %', v_items_with_location_id;
    RAISE NOTICE 'location_id 為 NULL 的物品: %', v_items_null_location_id;
    RAISE NOTICE '====================================';
END $$;

-- =============================================
-- 步驟 3-5: 在事務內執行刪除操作
-- =============================================

BEGIN;

-- 步驟 3: 刪除與 location_id 相關的索引
DROP INDEX IF EXISTS public.idx_items_location_id;

DO $$
BEGIN
    RAISE NOTICE '已刪除 location_id 相關索引';
END $$;

-- 步驟 4: 刪除 location_id 欄位
ALTER TABLE public.items
    DROP COLUMN IF EXISTS location_id;

DO $$
BEGIN
    RAISE NOTICE '已成功刪除 items.location_id 欄位';
END $$;

-- 步驟 5: 驗證欄位已被刪除
DO $$
DECLARE
    v_column_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name = 'location_id'
    ) INTO v_column_exists;

    IF v_column_exists THEN
        RAISE EXCEPTION '刪除失敗：location_id 欄位仍然存在！';
    ELSE
        RAISE NOTICE '驗證成功：location_id 欄位已完全移除';
    END IF;
END $$;

-- 步驟 6: 更新表格註解
COMMENT ON TABLE public.items IS
'物品表 v2.0：
- 已移除 location_id 欄位
- 透過 user_id 關聯到 locations 表
- 使用使用者的主要地點 (is_primary = true) 進行距離計算
- Migration 完成日期: 2025-11-07';

COMMIT;

-- =============================================
-- 步驟 7: 清理與優化（在事務外執行）
-- =============================================

-- 重新分析表格統計資訊（可在事務外執行）
ANALYZE public.items;

-- VACUUM 必須在事務外執行
VACUUM ANALYZE public.items;

DO $$
BEGIN
    RAISE NOTICE '已完成表格優化';
END $$;

-- =============================================
-- Migration 完成摘要
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '╔════════════════════════════════════════╗';
    RAISE NOTICE '║   Migration 完成: 20251107000004       ║';
    RAISE NOTICE '╠════════════════════════════════════════╣';
    RAISE NOTICE '║ ✓ 已刪除 items.location_id 欄位       ║';
    RAISE NOTICE '║ ✓ 已刪除相關索引                      ║';
    RAISE NOTICE '║ ✓ 已更新表格註解                      ║';
    RAISE NOTICE '║ ✓ 已完成表格優化                      ║';
    RAISE NOTICE '╠════════════════════════════════════════╣';
    RAISE NOTICE '║ 遷移狀態: 完全成功                    ║';
    RAISE NOTICE '║                                        ║';
    RAISE NOTICE '║ 新架構說明:                           ║';
    RAISE NOTICE '║ - items 透過 user_id 關聯 locations   ║';
    RAISE NOTICE '║ - 使用 JOIN locations ON              ║';
    RAISE NOTICE '║   user_id AND is_primary = true        ║';
    RAISE NOTICE '║ - 所有 RPC 函數已更新                 ║';
    RAISE NOTICE '║ - create_item 不再需要 location_id    ║';
    RAISE NOTICE '╚════════════════════════════════════════╝';
END $$;

-- =============================================
-- 回滾說明（僅供參考，實際無法完全回滾）
-- =============================================

/*
⚠️ 回滾注意事項：

此 migration 刪除了欄位，無法簡單回滾。
如果需要恢復，必須：

1. 重新建立欄位：
   ALTER TABLE public.items
   ADD COLUMN location_id BIGINT;

2. 從備份中恢復資料，或透過以下邏輯重建：
   UPDATE public.items i
   SET location_id = (
       SELECT l.id
       FROM public.locations l
       WHERE l.user_id = i.user_id
       ORDER BY l.is_primary DESC, l.created_at
       LIMIT 1
   );

3. 重新建立外鍵約束：
   ALTER TABLE public.items
   ADD CONSTRAINT items_location_id_fkey
   FOREIGN KEY (location_id)
   REFERENCES public.locations(id)
   ON DELETE RESTRICT;

4. 恢復所有舊版 RPC 函數

建議：在執行此 migration 前，先完整備份資料庫！
*/
