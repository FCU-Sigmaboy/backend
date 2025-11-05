import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { getAddressFromCoordinates } from './geocoding.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface SaveLocationRequest {
  latitude: number
  longitude: number
  type?: string
  is_primary?: boolean
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. 驗證請求方法
    if (req.method !== 'POST') {
      throw new Error('Method not allowed')
    }

    // 2. 取得認證 token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. 建立 Supabase 客戶端
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // 4. 驗證用戶身份
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. 解析請求 body
    const body: SaveLocationRequest = await req.json()
    let { latitude, longitude, type, is_primary } = body

    // 6. 驗證座標格式
    if (
      typeof latitude !== 'number' ||
      typeof longitude !== 'number' ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return new Response(
        JSON.stringify({ error: '無效的座標格式：緯度需在 -90 到 90 之間，經度需在 -180 到 180 之間' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 7. 驗證並設定地點類型
    const validTypes = ['家', '公司', '其他']
    if (type === undefined || type === null || type === '') {
      type = '其他'
      console.log('⚠️ 未指定地點類型，預設為「其他」')
    } else if (!validTypes.includes(type)) {
      return new Response(
        JSON.stringify({ 
          error: '無效的地點類型',
          valid_types: validTypes,
          received: type
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 8. 驗證並設定 is_primary
    if (typeof is_primary !== 'boolean') {
      // 檢查用戶是否已有地點
      const { data: existingLocations, error: countError } = await supabaseClient
        .from('locations')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', user.id)

      if (countError) {
        console.error('❌ 查詢用戶地點失敗:', countError)
        // 如果查詢失敗，預設為主要地點
        is_primary = true
      } else {
        // 如果是第一個地點，設為主要；否則設為非主要
        is_primary = (existingLocations === null || (existingLocations as any[]).length === 0)
        console.log(`ℹ️ 自動設定 is_primary: ${is_primary} (用戶${is_primary ? '首次' : '已有'}地點)`)
      }
    }

    // 9. 驗證 is_primary 邏輯：檢查是否與同類型地點衝突
    if (is_primary && type !== '其他') {
      const { data: existingPrimary, error: checkError } = await supabaseClient
        .from('locations')
        .select('id, type')
        .eq('user_id', user.id)
        .eq('type', type)
        .eq('is_primary', true)
        .limit(1)

      if (checkError) {
        console.warn('⚠️ 檢查主要地點失敗:', checkError)
      } else if (existingPrimary && existingPrimary.length > 0) {
        console.log(`ℹ️ 用戶已有「${type}」類型的主要地點，將取代為新地點`)
      }
    }

    console.log(`📍 處理用戶 ${user.id} 的地理位置: ${latitude}, ${longitude}`)
    console.log(`   類型: ${type}, 主要地點: ${is_primary}`)

    // 10. 呼叫 Google Maps Geocoding API
    let formattedAddress: string
    try {
      formattedAddress = await getAddressFromCoordinates(latitude, longitude)
      console.log(`✅ 行政區解析成功: ${formattedAddress}`)
    } catch (error) {
      console.error('❌ Geocoding 失敗:', error)
      return new Response(
        JSON.stringify({ 
          error: '地址解析失敗',
          details: error.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 11. 如果設為主要地點，先將該類型的其他主要地點設為非主要
    if (is_primary) {
      const { error: updateError } = await supabaseClient
        .from('locations')
        .update({ is_primary: false })
        .eq('user_id', user.id)
        .eq('type', type)

      if (updateError) {
        console.warn('⚠️ 更新其他主要地點失敗:', updateError)
        // 不中斷流程，繼續執行
      } else {
        console.log(`✅ 已將其他「${type}」類型的主要地點設為非主要`)
      }
    }

    // 12. 儲存到資料庫（使用 Service Role Key 繞過 RLS）
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 構建 WKT 格式的座標 (POINT(經度 緯度))
    const wktPoint = `POINT(${longitude} ${latitude})`

    console.log(`💾 儲存地點到資料庫: coordinates=${wktPoint}, formatted_address=${formattedAddress}`)

    const { data, error: insertError } = await supabaseAdmin
      .from('locations')
      .insert({
        user_id: user.id,
        coordinates: wktPoint,
        type: type,
        is_primary: is_primary,
        formatted_address: formattedAddress,
      })
      .select()
      .single()

    if (insertError) {
      console.error('❌ 資料庫插入失敗:', insertError)
      return new Response(
        JSON.stringify({ 
          error: '儲存地點失敗',
          details: insertError.message 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`✅ 地點儲存成功，ID: ${data.id}`)

    // 13. 返回成功結果
    return new Response(
      JSON.stringify({
        success: true,
        data: {
          id: data.id,
          latitude,
          longitude,
          district: formattedAddress,
          type,
          is_primary,
        },
        message: '地點儲存成功'
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('❌ 未預期的錯誤:', error)
    return new Response(
      JSON.stringify({ 
        error: '伺服器內部錯誤',
        details: error.message 
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
