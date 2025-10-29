/**
 * Supabase Edge Function: save-location
 *
 * 功能：安全地將使用者的地理位置儲存到資料庫
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
    // 1. 解析請求主體
    const { latitude, longitude, type = '其他', is_primary = false, formatted_address = null } = await req.json()

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

    // 3. 建立 Supabase Admin Client (使用 Service Role Key)
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

    // 4. 從請求的 Authorization header 中驗證使用者
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('Missing Authorization header')
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)

    if (userError || !user) {
      throw new Error('Unauthorized: Invalid or expired token')
    }

    // 5. 使用 PostGIS 的 ST_Point 函數建立地理點
    // 注意：PostGIS 的 POINT 格式是 (longitude, latitude)，不是 (latitude, longitude)
    const locationPoint = `POINT(${longitude} ${latitude})`

    // 6. 如果 is_primary 為 true，先將其他地點的 is_primary 設為 false
    if (is_primary) {
      await supabaseAdmin
        .from('locations')
        .update({ is_primary: false })
        .eq('user_id', user.id)
    }

    // 7. 將資料寫入資料庫
    const { data, error: insertError } = await supabaseAdmin
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

    // 8. 返回成功響應
    return new Response(
      JSON.stringify({
        success: true,
        message: 'Location saved successfully',
        data: {
          id: data.id,
          coordinates: {
            latitude,
            longitude
          },
          type: data.type,
          is_primary: data.is_primary,
          created_at: data.created_at
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

# 本地測試 (需要先啟動 supabase local)
curl -i --location --request POST 'http://localhost:54321/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0330, "longitude": 121.5654, "type": "家", "is_primary": true}'

# 遠端測試
curl -i --location --request POST 'https://your-project.supabase.co/functions/v1/save-location' \
  --header 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"latitude": 25.0330, "longitude": 121.5654, "type": "公司", "is_primary": false}'

*/
