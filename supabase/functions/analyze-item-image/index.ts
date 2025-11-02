// ====================================================================
// AI 物品圖片分析 Edge Function
// ====================================================================
// 建立日期: 2025-11-02
// 作者: Claude Code
// 功能: 使用 Google Gemini 1.5 Flash Vision API 分析物品圖片，提取物品資訊
// 修改日期: 2025-11-02 (改用 Gemini - 免費方案)
// ====================================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')

Deno.serve(async (req) => {
  // CORS 處理
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // 檢查 API Key 是否存在
    if (!GEMINI_API_KEY) {
      console.error('GEMINI_API_KEY is not set!')
      return new Response(
        JSON.stringify({
          error: 'GEMINI_API_KEY 環境變數未設定',
          details: 'Please set GEMINI_API_KEY in supabase/.env.local'
        }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }
    // 1. 驗證 JWT Token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: '未授權：缺少 Authorization header' }),
        {
          status: 401,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // 驗證使用者
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: '無效的 Token' }),
        {
          status: 401,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    console.log(`User ${user.id} is analyzing an image`)

    // 2. 解析請求資料
    const { image_url } = await req.json()

    if (!image_url) {
      return new Response(
        JSON.stringify({ error: '缺少 image_url 參數' }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    console.log(`Analyzing image: ${image_url}`)

    // 3. 從資料庫獲取所有分類
    const { data: categories, error: catError } = await supabase
      .from('sub_categories')
      .select(`
        id,
        name,
        default_carbon_value,
        main_categories (
          id,
          name
        )
      `)

    if (catError) {
      console.error('查詢分類失敗:', catError)
      return new Response(
        JSON.stringify({ error: '查詢分類失敗', details: catError.message }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    // 4. 建立分類列表供 AI 參考
    const categoryList = categories?.map(c =>
      `${c.id}: ${c.main_categories.name} > ${c.name} (預設碳值: ${c.default_carbon_value} kg)`
    ).join('\n') || ''

    console.log(`Found ${categories?.length} categories`)

    // 5. 先將圖片轉為 base64（Gemini 需要）
    let imageBase64 = ''
    let imageMimeType = 'image/jpeg'

    try {
      // 將外部 URL (127.0.0.1:54321) 轉換為 Docker 內部 URL
      // 在 Docker 容器內，通過 Kong API Gateway 存取
      let fetchUrl = image_url
      if (image_url.includes('127.0.0.1:54321') || image_url.includes('localhost:54321')) {
        // 本地開發環境：使用 Kong 容器作為 API Gateway
        fetchUrl = image_url
          .replace('http://127.0.0.1:54321', 'http://supabase_kong_backend:8000')
          .replace('http://localhost:54321', 'http://supabase_kong_backend:8000')
      }

      console.log(`Fetching image from: ${fetchUrl}`)
      const imageResponse = await fetch(fetchUrl)
      if (!imageResponse.ok) {
        throw new Error(`無法取得圖片: ${imageResponse.statusText}`)
      }

      const imageBlob = await imageResponse.blob()
      imageMimeType = imageBlob.type || 'image/jpeg'
      const arrayBuffer = await imageBlob.arrayBuffer()
      const bytes = new Uint8Array(arrayBuffer)

      // 使用更高效的 base64 編碼方式，避免 call stack overflow
      let binary = ''
      const len = bytes.byteLength
      for (let i = 0; i < len; i++) {
        binary += String.fromCharCode(bytes[i])
      }
      imageBase64 = btoa(binary)

      console.log(`圖片已轉換為 base64, MIME type: ${imageMimeType}`)
    } catch (error) {
      console.error('圖片轉換失敗:', error)
      return new Response(
        JSON.stringify({ error: '圖片處理失敗', details: error.message }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    // 6. 呼叫 Google Gemini Vision API
    // 使用 gemini-2.5-flash (穩定版本)
    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: `你是一個專業的二手物品分析專家。請根據圖片分析物品，並以繁體中文回答。

【可用的物品分類】
${categoryList}

【重要說明】
- 請仔細觀察圖片中的物品
- 根據物品的外觀、品牌、類型選擇最合適的分類
- 碳足跡值 (carbon_value) 可參考分類的預設值，但請根據物品實際大小、材質調整
- 如果圖片模糊或無法辨識，請在 warnings 中說明
- tags 請提供 3-5 個相關標籤，例如品牌、顏色、材質、用途等

【回傳格式】
請嚴格按照以下 JSON 格式回傳（不要包含任何其他文字）：
{
  "title": "物品名稱（簡短、具體，20字以內）",
  "description": "詳細描述（包含品牌、型號、尺寸、材質、功能、外觀特徵等，100-200字）",
  "sub_category_id": 分類ID（從上方列表選擇最合適的，必須是數字）,
  "carbon_value": 碳足跡值（預估 kg，數字，保留一位小數）,
  "tags": ["標籤1", "標籤2", "標籤3"],
  "confidence": 分析信心度（0-1之間的數字，例如 0.95）,
  "warnings": ["警告訊息1", "警告訊息2"]
}

【範例】
{
  "title": "IKEA 白色檯燈",
  "description": "IKEA 品牌的白色現代風格檯燈，高度約40公分，金屬燈座搭配布製燈罩，使用 E27 燈泡接口，適合書桌或床頭使用。外觀完整，功能正常。",
  "sub_category_id": 41,
  "carbon_value": 1.5,
  "tags": ["IKEA", "檯燈", "白色", "照明"],
  "confidence": 0.92,
  "warnings": []
}

請分析這個物品的圖片，提供詳細資訊。`
                },
                {
                  inline_data: {
                    mime_type: imageMimeType,
                    data: imageBase64
                  }
                }
              ]
            }
          ],
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 2000  // 增加到 2000，避免回應被截斷
          }
        })
      }
    )

    if (!geminiResponse.ok) {
      const errorText = await geminiResponse.text()
      console.error('Gemini API 錯誤:', errorText)
      return new Response(
        JSON.stringify({
          error: 'AI 分析失敗',
          details: errorText
        }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        }
      )
    }

    const aiResult = await geminiResponse.json()
    console.log('Gemini API 回應:', JSON.stringify(aiResult))

    // 檢查是否因為 MAX_TOKENS 被截斷
    const finishReason = aiResult.candidates?.[0]?.finishReason
    if (finishReason === 'MAX_TOKENS') {
      console.warn('警告: AI 回應因達到 token 限制而被截斷')
    }

    // 從 Gemini 回應中提取文字
    let generatedText = aiResult.candidates?.[0]?.content?.parts?.[0]?.text
    if (!generatedText) {
      throw new Error('Gemini API 未回傳有效內容')
    }

    // 移除 markdown 代碼塊標記（如果存在）
    generatedText = generatedText.trim()
    if (generatedText.startsWith('```json')) {
      generatedText = generatedText.replace(/^```json\s*\n/, '').replace(/\n```\s*$/, '')
    } else if (generatedText.startsWith('```')) {
      generatedText = generatedText.replace(/^```\s*\n/, '').replace(/\n```\s*$/, '')
    }

    // 嘗試修復不完整的 JSON
    let analysisResult
    try {
      analysisResult = JSON.parse(generatedText.trim())
    } catch (parseError) {
      console.error('JSON 解析失敗，嘗試修復...', parseError)
      // 嘗試補齊不完整的 JSON
      let fixedText = generatedText.trim()
      // 如果缺少結尾的 }
      if (!fixedText.endsWith('}')) {
        const openBraces = (fixedText.match(/{/g) || []).length
        const closeBraces = (fixedText.match(/}/g) || []).length
        const missingBraces = openBraces - closeBraces
        fixedText += '}'.repeat(missingBraces)
      }
      // 移除不完整的最後一個屬性（如果有的話）
      fixedText = fixedText.replace(/,\s*"[^"]*"\s*:\s*[^,}]*$/, '')
      fixedText = fixedText.trim()
      if (!fixedText.endsWith('}')) {
        fixedText += '}'
      }

      try {
        analysisResult = JSON.parse(fixedText)
        console.log('JSON 修復成功')
      } catch (fixError) {
        // 如果還是失敗，返回錯誤
        throw new Error(`無法解析 AI 回應: ${parseError.message}\n原始內容: ${generatedText.substring(0, 200)}...`)
      }
    }

    console.log('AI analysis completed:', analysisResult)

    // 7. 驗證回傳的 sub_category_id 是否存在
    const validCategory = categories?.find(c => c.id === analysisResult.sub_category_id)
    if (!validCategory) {
      analysisResult.warnings = analysisResult.warnings || []
      analysisResult.warnings.push('AI 選擇的分類不存在，請手動選擇分類')
      analysisResult.sub_category_id = null
    }

    // 8. 回傳成功結果
    return new Response(
      JSON.stringify({
        success: true,
        data: analysisResult,
        usage: aiResult.usageMetadata || {},
        model: 'gemini-1.5-flash'
      }),
      {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    )

  } catch (error) {
    console.error('處理請求時發生錯誤:', error)
    return new Response(
      JSON.stringify({
        error: '伺服器錯誤',
        message: error.message
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      }
    )
  }
})

/* 本地測試指令:

curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/analyze-item-image' \
  --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
  --header 'Content-Type: application/json' \
  --data '{"image_url":"https://your-image-url.jpg"}'

API Key 取得方式：
1. 前往 https://aistudio.google.com/app/apikey
2. 登入 Google 帳號
3. 點擊 "Create API Key"
4. 將 API Key 設定到 supabase/.env.local 中的 GEMINI_API_KEY

*/
