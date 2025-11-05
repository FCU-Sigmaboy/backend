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

    // 7. 驗證並設定地點類型（移除"其他"，只允許"家"和"公司"）
    const validTypes = ['家', '公司']

    // 檢查用戶現有地點
    const { data: existingLocations, error: checkError } = await supabaseClient
      .from('locations')
      .select('id, type, is_primary')
      .eq('user_id', user.id)

    if (checkError) {
      console.error('❌ 查詢用戶地點失敗:', checkError)
      return new Response(
        JSON.stringify({ error: '查詢用戶地點失敗', details: checkError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const hasExistingLocations = existingLocations && existingLocations.length > 0

    // 如果是首次建立地點，必須是"家"
    if (!hasExistingLocations) {
      if (type !== '家') {
        return new Response(
          JSON.stringify({
            error: '首次建立地點必須為「家」',
            received: type
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      type = '家'
      is_primary = true
      console.log('✅ 首次建立地點：自動設定為「家」且 is_primary=true')
    } else {
      // 已有地點的情況
      if (!type || type === '') {
        return new Response(
          JSON.stringify({
            error: '必須指定地點類型',
            valid_types: validTypes
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (!validTypes.includes(type)) {
        return new Response(
          JSON.stringify({
            error: '無效的地點類型（僅支援「家」和「公司」）',
            valid_types: validTypes,
            received: type
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // 檢查是否已有該類型的地點
      const existingTypeLocation = existingLocations.find(loc => loc.type === type)
      if (existingTypeLocation) {
        return new Response(
          JSON.stringify({
            error: `您已經有「${type}」類型的地點`,
            message: '每位用戶只能擁有一個「家」和一個「公司」'
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // 檢查地點數量限制
      if (existingLocations.length >= 2) {
        return new Response(
          JSON.stringify({
            error: '已達地點數量上限',
            message: '每位用戶最多只能擁有 2 個地點（家和公司）'
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // 8. 驗證並設定 is_primary（每位用戶全局只能有一個主要地點）
    if (!hasExistingLocations) {
      // 首次建立地點，必定為主要地點
      is_primary = true
    } else {
      // 已有地點的情況
      if (typeof is_primary !== 'boolean') {
        // 前端未指定，預設為 false
        is_primary = false
      }

      // 檢查是否已有主要地點
      const existingPrimaryLocation = existingLocations.find(loc => loc.is_primary === true)

      if (is_primary && existingPrimaryLocation) {
        // 如果新地點要設為主要，需要將現有主要地點改為非主要
        console.log(`ℹ️ 用戶已有主要地點（類型：${existingPrimaryLocation.type}），將設為非主要`)
      } else if (is_primary && !existingPrimaryLocation) {
        console.log('✅ 設定新地點為主要地點')
      } else if (!is_primary && !existingPrimaryLocation) {
        // 如果沒有主要地點，至少要有一個主要地點
        is_primary = true
        console.log('⚠️ 用戶沒有主要地點，自動將新地點設為主要')
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

    // 11. 如果設為主要地點，先將所有其他地點設為非主要（全局限制）
    if (is_primary) {
      const { error: updateError } = await supabaseClient
        .from('locations')
        .update({ is_primary: false })
        .eq('user_id', user.id)

      if (updateError) {
        console.warn('⚠️ 更新其他主要地點失敗:', updateError)
        // 不中斷流程，繼續執行
      } else {
        console.log(`✅ 已將用戶的所有其他地點設為非主要`)
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
