ㄌx-- ####################################################################
-- ### 更新個人 Profile (RPC)
-- ####################################################################

CREATE OR REPLACE FUNCTION public.update_my_profile(
    p_user_data JSONB,      -- 包含 { "nickname": "...", "profile_picture_url": "..." }
    p_profile_data JSONB,   -- 包含 { "balance": ... } (謹慎使用)
    p_locations_data JSONB  -- 包含一個 location 物件的 "陣列"
                            -- [{ "id": 12, "coordinates": ..., "is_primary": true, ...}, { "coordinates": ..., "is_primary": false, ...}]
)
RETURNS JSON -- 回傳更新後的完整資料 (profile + locations)
AS $$
DECLARE
v_current_uid UUID := auth.uid();
  v_updated_user users;
  v_updated_profile profiles;
  loc RECORD;
  updated_loc_ids BIGINT[] := ARRAY[]::BIGINT[];
  new_loc_ids BIGINT[] := ARRAY[]::BIGINT[];
  primary_loc_id BIGINT;
  v_geography GEOGRAPHY(Point, 4326);
BEGIN
  -- 1. 安全檢查：確認使用者已登入
  IF v_current_uid IS NULL THEN
    RAISE EXCEPTION '使用者未登入';
END IF;

  -- 2. 更新 public.users 表
UPDATE public.users
SET
    nickname = COALESCE(p_user_data->>'nickname', nickname),
    profile_picture_url = COALESCE(p_user_data->>'profile_picture_url', profile_picture_url)
WHERE id = v_current_uid
    RETURNING * INTO v_updated_user;

-- 3. 更新 public.profiles 表 (謹慎處理允許更新的欄位)
UPDATE public.profiles
SET
    balance = COALESCE((p_profile_data->>'balance')::INT, balance),
    -- carbon_saved_kg 通常應由後端計算，此處不更新
    updated_at = NOW()
WHERE user_id = v_current_uid
    RETURNING * INTO v_updated_profile;

-- 4. 處理 locations (Upsert)
FOR loc IN SELECT * FROM jsonb_to_recordset(p_locations_data) AS x(
                                                                   id BIGINT,
                                                                   coordinates JSONB,
                                                                   type TEXT,
                                                                   is_primary BOOLEAN,
                                                                   formatted_address TEXT
    )
    LOOP
    -- 轉換 coordinates JSON 為 GEOGRAPHY
    v_geography := ST_MakePoint(
      (loc.coordinates->>'longitude')::double precision,
      (loc.coordinates->>'latitude')::double precision
    )::geography;

IF loc.id IS NOT NULL THEN
      -- 更新現有 location (必須確保是自己的)
UPDATE public.locations
SET
    coordinates = v_geography,
    type = loc.type,
    is_primary = loc.is_primary, -- 先暫存 is_primary 狀態
    formatted_address = loc.formatted_address,
    updated_at = NOW()
WHERE id = loc.id AND user_id = v_current_uid;
updated_loc_ids := array_append(updated_loc_ids, loc.id);
      IF loc.is_primary THEN
         primary_loc_id := loc.id;
END IF;
ELSE
      -- 插入新 location
      INSERT INTO public.locations (user_id, coordinates, type, is_primary, formatted_address)
      VALUES (v_current_uid, v_geography, loc.type, loc.is_primary, loc.formatted_address)
      RETURNING id INTO loc.id; -- 獲取新 ID
      new_loc_ids := array_append(new_loc_ids, loc.id);
       IF loc.is_primary THEN
         primary_loc_id := loc.id;
END IF;
END IF;
END LOOP;

  -- 5. 確保只有一個 primary location
  IF primary_loc_id IS NOT NULL THEN
      -- 將所有 "非主" 的地點設為 is_primary = false
UPDATE public.locations
SET is_primary = false
WHERE user_id = v_current_uid AND id != primary_loc_id;
-- 確保 "主" 地點設為 is_primary = true (即使前端傳錯)
UPDATE public.locations
SET is_primary = true
WHERE user_id = v_current_uid AND id = primary_loc_id;
ELSE
     -- 如果前端沒指定 primary，預設將第一個設為 primary (可選邏輯)
     -- UPDATE public.locations SET is_primary = true WHERE id = (SELECT id FROM public.locations WHERE user_id = v_current_uid ORDER BY id LIMIT 1);
     -- 或者全部設為 false
UPDATE public.locations SET is_primary = false WHERE user_id = v_current_uid;
END IF;

  -- 6. 查詢所有更新/新增後的 locations
SELECT json_agg(l ORDER BY l.is_primary DESC, l.id ASC)
INTO v_updated_locations
FROM public.locations l
WHERE l.user_id = v_current_uid;

-- 7. 回傳合併後的 DTO
RETURN json_build_object(
        'id', v_updated_user.id,
        'nickname', v_updated_user.nickname,
        'profile_picture_url', v_updated_user.profile_picture_url,
        'avg_rating', v_updated_user.avg_rating,
        'profile_details', json_build_object(
                'balance', v_updated_profile.balance,
                'carbon_saved_kg', v_updated_profile.carbon_saved_kg,
                'updated_at', v_updated_profile.updated_at
                           ),
        'locations', COALESCE(v_updated_locations, '[]'::json)
       );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;