/**
 * Supabase Edge Function: save-location
 *
 * 功能：
 * 1. GET 請求：獲取使用者已儲存的主要位置
 * 2. POST 請求：儲存或更新使用者的地理位置
 *
 * 使用現有的 locations 表結構：
 * - id: BIGSERIAL (自動生成)
 * - user_id: UUID (從認證 token 取得)
 * - coordinates: GEOGRAPHY(Point, 4326) (PostGIS 地理點)
 * - type: VARCHAR(50) (地點類型：'家'、'公司'、'其他')
 * - is_primary: BOOLEAN (是否為主要地點)
 * - formatted_address: TEXT (格式化地址，選填)
 * - created_at, updated_at: TIMESTAMPTZ (自動管理)
 *
 * 邏輯：
 * - GET：查詢使用者的主要位置（is_primary = true），返回經緯度座標
 * - POST：首次呼叫時 INSERT 新記錄，後續呼叫時 UPDATE 現有記錄（避免重複）
 *
 * 安全性：
 * - 使用 Service Role Key 進行認證
 * - 從 JWT token 驗證使用者身份
 * - RLS 策略會自動確保資料隔離
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// Deno.serve 是 Supabase Edge Functions 的標準入口
Deno.serve(async (req) => {
  // 處理 CORS Preflight 請求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 建立 Supabase Admin Client (使用 Service Role Key)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // 從請求的 Authorization header 中驗證使用者
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('Missing Authorization header')
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)

    if (userError || !user) {
      throw new Error('Unauthorized: Invalid or expired token')
    }

    // === 處理 GET 請求：獲取使用者已儲存的位置 ===
    if (req.method === 'GET') {
      // 使用原始 SQL 查詢，直接提取座標
      const { data: locationData, error: fetchError } = await supabaseAdmin
        .rpc('get_user_primary_location', { p_user_id: user.id })

      if (fetchError) {
        console.error('Database fetch error:', fetchError)
        throw new Error(`Failed to fetch location: ${fetchError.message}`)
      }

      // 如果沒有儲存的位置
      if (!locationData || locationData.length === 0) {
        return new Response(
          JSON.stringify({
            success: true,
            hasLocation: false,
            data: null
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
          }
        )
      }

      const location = locationData[0]

      return new Response(
        JSON.stringify({
          success: true,
          hasLocation: true,
          data: {
            id: location.id,
            coordinates: {
              latitude: location.latitude,
              longitude: location.longitude
            },
            type: location.type,
            is_primary: location.is_primary,
            formatted_address: location.formatted_address,
            created_at: location.created_at,
            updated_at: location.updated_at
          }
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        }
      )
    }

    // === 處理 POST 請求：儲存或更新位置 ===
    if (req.method !== 'POST') {
      throw new Error('Method not allowed. Use GET to fetch location or POST to save/update location.')
    }

    // 1. 解析請求主體
    const { latitude, longitude, type = '其他', is_primary = true, formatted_address = null } = await req.json()

    // 2. 驗證輸入
    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      throw new Error('Invalid coordinates: latitude and longitude must be numbers')
    }

    if (latitude < -90 || latitude > 90) {
      throw new Error('Invalid latitude: must be between -90 and 90')
    }

    if (longitude < -180 || longitude > 180) {
      throw new Error('Invalid longitude: must be between -180 and 180')
    }

    const validTypes = ['家', '公司', '其他']
    if (!validTypes.includes(type)) {
      throw new Error(`Invalid type: must be one of ${validTypes.join(', ')}`)
    }

    // 3. 使用 PostGIS 的 ST_Point 函數建立地理點
    // 注意：PostGIS 的 POINT 格式是 (longitude, latitude)，不是 (latitude, longitude)
    const locationPoint = `POINT(${longitude} ${latitude})`

    // 4. 檢查使用者是否已有主要位置
    const { data: existingLocation, error: checkError } = await supabaseAdmin
      .from('locations')
      .select('*')
      .eq('user_id', user.id)
      .eq('is_primary', true)
      .maybeSingle()

    if (checkError) {
      console.error('Database check error:', checkError)
      throw new Error(`Failed to check existing location: ${checkError.message}`)
    }

    let data
    let isNewLocation = false

    // 5. 如果已有主要位置，更新它；否則插入新記錄
    if (existingLocation) {
      // 使用者已有位置，更新現有記錄
      const { data: updatedData, error: updateError } = await supabaseAdmin
        .from('locations')
        .update({
          coordinates: locationPoint,
          type: type,
          formatted_address: formatted_address,
          updated_at: new Date().toISOString()
        })
        .eq('id', existingLocation.id)
        .select()
        .single()

      if (updateError) {
        console.error('Database update error:', updateError)
        throw new Error(`Failed to update location: ${updateError.message}`)
      }
      data = updatedData
    } else {
      // 首次設定位置，插入新記錄
      isNewLocation = true

      // 如果 is_primary 為 true，先將其他地點的 is_primary 設為 false
      if (is_primary) {
        await supabaseAdmin
          .from('locations')
          .update({ is_primary: false })
          .eq('user_id', user.id)
      }

      const { data: insertedData, error: insertError } = await supabaseAdmin
        .from('locations')
        .insert({
          user_id: user.id,
          coordinates: locationPoint,
          type: type,
          is_primary: is_primary,
          formatted_address: formatted_address
        })
        .select()
        .single()

      if (insertError) {
        console.error('Database insert error:', insertError)
        throw new Error(`Failed to save location: ${insertError.message}`)
      }
      data = insertedData
    }

    // 6. 返回成功響應
    return new Response(
      JSON.stringify({
        success: true,
        message: isNewLocation ? 'Location saved successfully' : 'Location updated successfully',
        isNewLocation: isNewLocation,
        data: {
          id: data.id,
          coordinates: {
            latitude,
            longitude
          },
          type: data.type,
          is_primary: data.is_primary,
          formatted_address: data.formatted_address,
          created_at: data.created_at,
          updated_at: data.updated_at
        }
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('Error in save-location function:', error)

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || 'Internal server error'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})

/* 測試用 curl 命令：

=== GET 請求：獲取已儲存的位置 ===

# 本地測試
curl -i --location --request GET 'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN'

# 回應範例（有位置）：
# {
#   "success": true,
#   "hasLocation": true,
#   "data": {
#     "id": 1,
#     "coordinates": {"latitude": 25.0330, "longitude": 121.5654},
#     "type": "其他",
#     "is_primary": true,
#     "formatted_address": "台北市信義區...",
#     "created_at": "2025-10-31T...",
#     "updated_at": "2025-10-31T..."
#   }
# }

# 回應範例（無位置）：
# {"success": true, "hasLocation": false, "data": null}

=== POST 請求：儲存或更新位置 ===

# 首次儲存（會 INSERT）
curl -i --location --request POST 'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0330, "longitude": 121.5654, "type": "家", "is_primary": true}'

# 回應：{"success": true, "message": "Location saved successfully", "isNewLocation": true, ...}

# 第二次呼叫（會 UPDATE）
curl -i --location --request POST 'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0400, "longitude": 121.5700, "formatted_address": "台北市..."}'

# 回應：{"success": true, "message": "Location updated successfully", "isNewLocation": false, ...}

=== 遠端測試 ===
curl -i --location --request GET 'https://your-project.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN'

*/
