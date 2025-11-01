-- Single Item Detail RPC - Optimized Version v2.5
-- Date: 2025-11-01

CREATE OR REPLACE FUNCTION public.get_item_details_with_location(
    p_item_id BIGINT
)
    RETURNS JSONB
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_current_uid UUID;
    v_item_details JSONB;
BEGIN
    IF p_item_id IS NULL OR p_item_id <= 0 THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INVALID_PARAMETER',
            'message', '無效的物品 ID',
            'item_id', p_item_id
        );
    END IF;

    v_current_uid := auth.uid();

    WITH
    user_location AS (
        SELECT
            coordinates,
            CASE
                WHEN is_primary THEN 'database_primary'
                ELSE 'database_fallback'
            END as location_source
        FROM public.locations
        WHERE user_id = v_current_uid
          AND v_current_uid IS NOT NULL
        ORDER BY
            is_primary DESC NULLS LAST,
            created_at
        LIMIT 1
    ),
    item_data AS (
        SELECT
            i.id,
            i.title,
            i.description,
            i.condition,
            i.listing_status,
            i.price,
            i.carbon_value,
            i.image_urls,
            i.tags,
            i.created_at,
            i.updated_at,
            i.user_id as owner_id,
            u.id as seller_id,
            u.nickname as seller_nickname,
            u.profile_picture_url as seller_avatar,
            u.avg_rating as seller_rating,
            seller_loc.id as location_id,
            seller_loc.formatted_address as location_address,
            seller_loc.type as location_type,
            seller_loc.coordinates as seller_coordinates,
            sc.id as sub_category_id,
            sc.name as sub_category_name,
            mc.id as main_category_id,
            mc.name as main_category_name,
            mc.icon as main_category_icon,
            mc.color as main_category_color,
            (fav.item_id IS NOT NULL) as is_favorited,
            ul.coordinates as user_coordinates,
            ul.location_source as user_location_source
        FROM public.items i
        INNER JOIN public.users u ON i.user_id = u.id
        LEFT JOIN public.locations seller_loc ON i.user_id = seller_loc.user_id AND seller_loc.is_primary = true
        LEFT JOIN public.sub_categories sc ON i.sub_category_id = sc.id
        LEFT JOIN public.main_categories mc ON sc.main_category_id = mc.id
        LEFT JOIN public.favorites fav ON fav.item_id = i.id AND fav.user_id = v_current_uid
        LEFT JOIN LATERAL (SELECT * FROM user_location) ul ON true
        WHERE i.id = p_item_id
          AND i.listing_status = true
    )
    SELECT
        jsonb_build_object(
            'id', id,
            'title', title,
            'description', description,
            'condition', condition,
            'listing_status', listing_status,
            'price', price,
            'carbon_value', carbon_value,
            'image_urls', image_urls,
            'tags', tags,
            'created_at', created_at,
            'updated_at', updated_at,
            'distance_km', CASE
                WHEN v_current_uid IS NOT NULL
                    AND v_current_uid != owner_id
                    AND seller_coordinates IS NOT NULL THEN
                    ROUND((ST_Distance(seller_coordinates, user_coordinates) / 1000.0)::numeric, 3)
            END,
            'is_favorited', is_favorited,
            'is_owner', CASE
                WHEN v_current_uid IS NOT NULL THEN (owner_id = v_current_uid)
                ELSE false
            END,
            'location', jsonb_build_object(
                'id', location_id,
                'formatted_address', location_address,
                'type', location_type,
                'coordinates', CASE
                    WHEN v_current_uid IS NOT NULL
                        AND v_current_uid != owner_id
                        AND seller_coordinates IS NOT NULL THEN
                        ST_AsGeoJSON(seller_coordinates)::jsonb
                END
            ),
            'user', jsonb_build_object(
                'id', seller_id,
                'nickname', seller_nickname,
                'profile_picture_url', seller_avatar,
                'avg_rating', seller_rating
            ),
            'category', jsonb_build_object(
                'sub_category_id', sub_category_id,
                'sub_category_name', sub_category_name,
                'main_category_id', main_category_id,
                'main_category_name', main_category_name,
                'main_category_icon', main_category_icon,
                'main_category_color', main_category_color
            ),
            'user_location', CASE
                WHEN v_current_uid IS NOT NULL
                    AND v_current_uid != owner_id THEN
                    CASE
                        WHEN user_coordinates IS NOT NULL THEN
                            jsonb_build_object(
                                'has_location', true,
                                'source', user_location_source,
                                'coordinates', ST_AsGeoJSON(user_coordinates)::jsonb,
                                'message', CASE user_location_source
                                    WHEN 'database_primary' THEN '使用您的主要地點'
                                    WHEN 'database_fallback' THEN '使用您設定的地點'
                                    ELSE '位置來源未知'
                                END
                            )
                        ELSE
                            jsonb_build_object(
                                'has_location', false,
                                'source', 'none',
                                'message', '無法取得位置資訊，請在個人資料中設定地點'
                            )
                    END
            END
        )
    INTO v_item_details
    FROM item_data;

    IF v_item_details IS NULL THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'ITEM_NOT_FOUND',
            'message', '物品不存在或已下架',
            'item_id', p_item_id
        );
    END IF;

    RETURN v_item_details;

EXCEPTION
    WHEN no_data_found THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'ITEM_NOT_FOUND',
            'message', '找不到指定的物品',
            'item_id', p_item_id
        );
    WHEN invalid_parameter_value THEN
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INVALID_PARAMETER',
            'message', '參數格式錯誤',
            'item_id', p_item_id,
            'detail', SQLERRM
        );
    WHEN OTHERS THEN
        RAISE WARNING '查詢物品詳情時發生錯誤: % (item_id: %)', SQLERRM, p_item_id;
        RETURN jsonb_build_object(
            'error', true,
            'code', 'INTERNAL_ERROR',
            'message', '查詢過程發生錯誤，請稍後再試',
            'item_id', p_item_id
        );
END;
$$;

COMMENT ON FUNCTION public.get_item_details_with_location(BIGINT) IS
'取得單一物品詳情，包含距離計算和隱私保護 - v2.5';

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

